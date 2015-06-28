require_relative '../../mutations/host_nodes/register'

module V1
  class NodesApi < Roda
    include RequestHelpers

    plugin :json
    plugin :render, engine: 'jbuilder', ext: 'json.jbuilder', views: 'app/views/v1'
    plugin :error_handler do |e|
      response.status = 500
      log_message = "\n#{e.class} (#{e.message}):\n"
      log_message << "  " << e.backtrace.join("\n  ") << "\n\n"
      request.logger.error log_message
      { message: 'Internal server error' }
    end

    route do |r|
      r.post do
        r.is do
          token = r.env['HTTP_KONTENA_GRID_TOKEN']
          data = parse_json_body

          grid = Grid.find_by(token: token.to_s)
          if !grid
            halt_request(404, {error: 'Not found'})
          end
          @node = grid.host_nodes.find_by(node_id: data['id'])
          response.status = 200
          unless @node
            response.status = 201
            outcome = HostNodes::Register.run(grid: grid, id: data['id'])
            unless outcome.success?
              halt_request(422, {error: outcome.errors.message})
            end
            @node = outcome.result
          end

          render('host_nodes/show')
        end
      end
    end
  end
end
