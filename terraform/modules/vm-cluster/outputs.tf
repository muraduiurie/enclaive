# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

output "node_inventory" {
  description = "Map of node name to its properties (ip, role, cpus, memory_mb)"
  value = {
    for node in local.nodes : node.name => {
      ip        = node.ip
      role      = node.role
      cpus      = node.cpus
      memory_mb = node.memory_mb
    }
  }
}

output "control_plane_ip" {
  description = "IP address of the first (primary) control-plane node"
  value       = local.control_plane_nodes[0].ip
}

output "worker_ips" {
  description = "List of worker node IP addresses"
  value       = [for n in local.worker_nodes : n.ip]
}

output "vagrantfile_path" {
  description = "Absolute path to the rendered Vagrantfile"
  value       = local_file.vagrantfile.filename
}

output "vagrantfile_sha256" {
  description = "SHA256 hash of the Vagrantfile content — used as a trigger in vagrant-lifecycle"
  value       = local_file.vagrantfile.content_sha256
}

output "vagrantfile_dir" {
  description = "Directory containing the rendered Vagrantfile"
  value       = var.vagrantfile_dir
}
