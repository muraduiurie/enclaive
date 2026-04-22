# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

output "cluster_ready" {
  description = "True after vagrant up completes. Use as depends_on anchor in downstream modules."
  value       = true
  depends_on  = [null_resource.vagrant_up]
}

output "ssh_config_path" {
  description = "Path to the vagrant ssh-config output file"
  value       = "${var.vagrantfile_dir}/.vagrant/ssh-config"
  depends_on  = [null_resource.vagrant_inventory]
}

output "inventory_path" {
  description = "Path to the generated Ansible inventory file"
  value       = "${var.ansible_inventory_dir}/${var.cluster_name}.ini"
  depends_on  = [null_resource.vagrant_inventory]
}
