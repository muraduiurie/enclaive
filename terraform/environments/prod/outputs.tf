# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

output "control_plane_ip" {
  description = "IP of the control-plane node"
  value       = module.vm_cluster.control_plane_ip
}

output "worker_ips" {
  description = "IPs of all worker nodes"
  value       = module.vm_cluster.worker_ips
}

output "vagrantfile_path" {
  description = "Path to the generated Vagrantfile"
  value       = module.vm_cluster.vagrantfile_path
}

output "ansible_inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = module.ssh_config.inventory_path
}

output "next_step" {
  description = "Command to run after terraform apply"
  value       = "ansible-playbook -i ${module.ssh_config.inventory_path} ../../../ansible/playbooks/bootstrap.yml"
}
