# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

locals {
  # Absolute path to this environment directory — used to write generated artifacts
  env_dir              = abspath(path.module)
  ansible_inventory_dir = abspath("${path.module}/../../../ansible/inventory")
}

module "vm_cluster" {
  source = "../../modules/vm-cluster"

  cluster_name            = var.cluster_name
  box_name                = var.box_name
  box_version             = var.box_version
  control_plane_count     = var.control_plane_count
  worker_count            = var.worker_count
  control_plane_cpus      = var.control_plane_cpus
  control_plane_memory_mb = var.control_plane_memory_mb
  worker_cpus             = var.worker_cpus
  worker_memory_mb        = var.worker_memory_mb
  private_network_prefix  = var.private_network_prefix
  vagrantfile_dir         = local.env_dir
  ssh_public_key_path     = var.ssh_public_key_path
}

module "vagrant_lifecycle" {
  source = "../../modules/vagrant-lifecycle"

  cluster_name       = var.cluster_name
  vagrantfile_dir    = module.vm_cluster.vagrantfile_dir
  vagrantfile_sha256 = module.vm_cluster.vagrantfile_sha256
}

module "ssh_config" {
  source = "../../modules/ssh-config"

  cluster_name          = var.cluster_name
  node_inventory        = module.vm_cluster.node_inventory
  ssh_config_path       = module.vagrant_lifecycle.ssh_config_path
  ansible_inventory_dir = local.ansible_inventory_dir
  ssh_private_key_path  = var.ssh_private_key_path
  ansible_user          = "vagrant"
}
