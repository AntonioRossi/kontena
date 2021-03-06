require 'celluloid'
require_relative 'logging'
require_relative 'grid_service_scheduler'

class GridServiceDeployer
  include Logging
  include DistributedLocks

  class NodeMissingError < StandardError; end
  class DeployError < StandardError; end

  DEFAULT_REGISTRY = 'index.docker.io'

  attr_reader :grid_service, :nodes, :scheduler

  ##
  # @param [#find_node] strategy
  # @param [GridService] grid_service
  # @param [Array<HostNode>] nodes
  def initialize(strategy, grid_service, nodes)
    @scheduler = GridServiceScheduler.new(strategy)
    @grid_service = grid_service
    @nodes = nodes
  end

  ##
  # Is deploy possible?
  #
  # @return [Boolean]
  def can_deploy?
    self.grid_service.container_count.times do |i|
      node = self.scheduler.select_node(
        self.grid_service, i + 1, self.nodes
      )
      return false unless node
    end

    true
  end

  # @return [Array<HostNode>]
  def selected_nodes
    nodes = []
    self.grid_service.container_count.times do |i|
      node = self.scheduler.select_node(
        self.grid_service, i + 1, self.nodes
      )
      nodes << node if node
    end

    nodes
  end

  def deploy
    info "starting to deploy #{self.grid_service.to_path}"
    creds = self.creds_for_registry
    self.grid_service.set_state('deploying')
    self.grid_service.set(:deployed_at => Time.now.utc)

    deploy_rev = Time.now.utc.to_s
    deploy_futures = []
    %w(TERM).each do |signal|
      Signal.trap(signal) { self.grid_service.set_state('running') }
    end
    total_instances = self.scheduler.instance_count(self.nodes.size, self.grid_service.container_count)
    total_instances.times do |i|
      instance_number = i + 1
      unless self.grid_service.deploying?
        raise "halting deploy of #{self.grid_service.to_path}, desired state has changed"
      end
      self.deploy_service_instance(total_instances, deploy_futures, instance_number, deploy_rev, creds)
      sleep 0.1
    end
    deploy_futures.select{|f| !f.ready?}.each{|f| f.value }

    self.cleanup_deploy(total_instances, deploy_rev)

    info "service #{self.grid_service.to_path} has been deployed"
    self.grid_service.set_state('running')

    true
  rescue NodeMissingError => exc
    self.grid_service.set_state('running')
    error exc.message
    info "service #{self.grid_service.to_path} deploy cancelled"
    false
  rescue DeployError => exc
    self.grid_service.set_state('running')
    error exc.message
    false
  rescue RpcClient::Error => exc
    self.grid_service.set_state('running')
    error "Rpc error (#{self.grid_service.to_path}): #{exc.class.name} #{exc.message}"
    error exc.backtrace.join("\n") if exc.backtrace
    false
  rescue => exc
    self.grid_service.set_state('running')
    error "Unknown error (#{self.grid_service.to_path}): #{exc.class.name} #{exc.message}"
    error exc.backtrace.join("\n") if exc.backtrace
    false
  end

  # @param [Integer] total_instances
  # @param [Array<Celluloid::Future>] deploy_futures
  # @param [Integer] instance_number
  # @param [String] deploy_rev
  # @param [Hash, NilClass] creds
  def deploy_service_instance(total_instances, deploy_futures, instance_number, deploy_rev, creds)
    node = self.scheduler.select_node(
        self.grid_service, instance_number, self.nodes
    )
    unless node
      raise NodeMissingError.new("Cannot find applicable node for service instance #{self.grid_service.to_path}-#{instance_number}")
    end
    info "deploying service instance #{self.grid_service.to_path}-#{instance_number} to node #{node.name}"
    deploy_futures << Celluloid::Future.new {
      instance_deployer = GridServiceInstanceDeployer.new(self.grid_service)
      instance_deployer.deploy(node, instance_number, deploy_rev, creds)
    }
    pending_deploys = deploy_futures.select{|f| !f.ready?}
    if pending_deploys.size >= (total_instances * self.min_health).floor || pending_deploys.size >= 20
      info "throttling service instance #{self.grid_service.to_path} deploy because of min_health limit (#{pending_deploys.size} instances in-progress)"
      pending_deploys[0].value rescue nil
      sleep 0.1 until pending_deploys.any?{|f| f.ready?}
    end
    if deploy_futures.any?{|f| f.ready? && f.value == false}
      raise DeployError.new("halting deploy of #{self.grid_service.to_path}, one or more instances failed")
    end
  end

  # @param [String] deploy_rev
  def cleanup_deploy(total_instances, deploy_rev)
    cleanup_futures = []
    self.grid_service.containers.where(:deploy_rev => {:$ne => deploy_rev}).each do |container|
      instance_number = container.name.match(/^.+-(\d+)$/)[1]
      container.set(:deleted_at => Time.now.utc)

      instance_deployer = GridServiceInstanceDeployer.new(self.grid_service)
      # just to be on a safe side.. we don't want to destroy anything accidentally
      if instance_number.to_i <= total_instances
        deployed_container = instance_deployer.find_service_instance_container(instance_number, deploy_rev)
        if deployed_container.nil?
          next
        elsif deployed_container.host_node_id == container.host_node_id
          next
        end
      end

      cleanup_futures << Celluloid::Future.new {
        info "removing service instance #{container.to_path}"
        instance_deployer.terminate_service_instance(instance_number, container.host_node)
      }
      pending_cleanups = cleanup_futures.select{|f| !f.ready?}
      if pending_cleanups.size > self.nodes.size
        pending_cleanups[0].value rescue nil
      end
    end
    self.grid_service.containers.unscoped.where(:container_id => nil, :deploy_rev => {:$ne => deploy_rev}).each do |container|
      container.destroy
    end
  end

  # @return [Integer]
  def instance_count
    self.scheduler.instance_count(self.nodes.size, self.grid_service.container_count)
  end

  # @return [Float]
  def min_health
    1.0 - (self.grid_service.deploy_opts.min_health || 0.8).to_f
  end

  # @return [Hash,NilClass]
  def creds_for_registry
    registry = self.grid_service.grid.registries.find_by(name: self.registry_name)
    if registry
      registry.to_creds
    end
  end

  # @return [String]
  def registry_name
    image_name = self.grid_service.image_name.to_s
    return DEFAULT_REGISTRY unless image_name.include?('/')

    name = image_name.to_s.split('/')[0]
    if name.match(/(\.|:)/)
      name
    else
      DEFAULT_REGISTRY
    end
  end
end
