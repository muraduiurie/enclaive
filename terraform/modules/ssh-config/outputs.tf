# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

output "inventory_path" {
  description = "Absolute path to the generated Ansible inventory file"
  value       = local_file.ansible_inventory.filename
}

output "control_plane_nodes" {
  description = "Map of control-plane node names to their IPs"
  value       = { for name, node in local.control_plane_nodes : name => node.ip }
}

output "worker_nodes" {
  description = "Map of worker node names to their IPs"
  value       = { for name, node in local.worker_nodes : name => node.ip }
}
