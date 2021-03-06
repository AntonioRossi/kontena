json.id node.node_id
json.connected node.connected
json.created_at node.created_at
json.updated_at node.updated_at
json.last_seen_at node.last_seen_at
json.name node.name
json.os node.os
json.driver node.driver
json.kernel_version node.kernel_version
json.labels node.labels
json.mem_total node.mem_total
json.mem_limit node.mem_limit
json.cpus node.cpus
json.public_ip node.public_ip
json.private_ip node.private_ip
json.peer_ips node.grid.host_nodes.ne(id: node.id).map{|node| node.private_ip}.compact
json.node_number node.node_number
json.grid do
  json.partial!("app/views/v1/grids/grid", grid: node.grid) if node.grid
end
