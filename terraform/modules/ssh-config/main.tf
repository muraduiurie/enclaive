# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

locals {
  control_plane_nodes = {
    for name, node in var.node_inventory : name => node
    if node.role == "control-plane"
  }
  worker_nodes = {
    for name, node in var.node_inventory : name => node
    if node.role == "worker"
  }
}

# Render the Ansible inventory file for this cluster/environment
resource "local_file" "ansible_inventory" {
  filename        = "${var.ansible_inventory_dir}/${var.cluster_name}.ini"
  content         = templatefile("${path.module}/templates/inventory.ini.tpl", {
    cluster_name         = var.cluster_name
    control_plane_nodes  = local.control_plane_nodes
    worker_nodes         = local.worker_nodes
    ssh_private_key_path = pathexpand(var.ssh_private_key_path)
    ansible_user         = var.ansible_user
  })
  file_permission = "0644"
}
