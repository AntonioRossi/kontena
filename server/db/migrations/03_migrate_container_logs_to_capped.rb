class MigrateContainerLogsToCapped < Mongodb::Migration

  def self.up
    unless ContainerLog.collection.capped?
      size = (ENV['CONTAINER_LOGS_CAPPED_SIZE'] || 5000).to_i
      ContainerLog.collection.session.command(
        convertToCapped: ContainerLog.collection.name,
        capped: true,
        size: size.megabytes
      )
    end
  end
end
