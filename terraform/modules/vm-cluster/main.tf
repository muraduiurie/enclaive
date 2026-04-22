# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

locals {
  # Build a flat list of all nodes with their properties
  # SSH ports must be unique per VM on the host.
  # vagrant-qemu defaults all VMs to 50022, causing port collisions.
  # Control-plane nodes start at ssh_port_base, workers follow sequentially.
  control_plane_nodes = [
    for i in range(var.control_plane_count) : {
      name      = "${var.cluster_name}-cp-${i}"
      ip        = "${var.private_network_prefix}.${10 + i}"
      role      = "control-plane"
      cpus      = var.control_plane_cpus
      memory_mb = var.control_plane_memory_mb
      ssh_port  = var.ssh_port_base + i
    }
  ]

  worker_nodes = [
    for i in range(var.worker_count) : {
      name      = "${var.cluster_name}-worker-${i}"
      ip        = "${var.private_network_prefix}.${11 + i}"
      role      = "worker"
      cpus      = var.worker_cpus
      memory_mb = var.worker_memory_mb
      ssh_port  = var.ssh_port_base + var.control_plane_count + i
    }
  ]

  nodes = concat(local.control_plane_nodes, local.worker_nodes)
}

# Render the Vagrantfile from a template and write it to the environment directory.
# This file is a generated artifact — it is .gitignore'd and re-created on apply.
resource "local_file" "vagrantfile" {
  filename        = "${var.vagrantfile_dir}/Vagrantfile"
  content         = templatefile("${path.module}/templates/Vagrantfile.tpl", {
    nodes               = local.nodes
    box_name            = var.box_name
    box_version         = var.box_version
    cluster_net         = var.private_network_prefix
    mcast_port          = var.mcast_port
    # pathexpand() resolves ~ to an absolute path — Ruby's File.readlines does not expand ~ natively.
    ssh_public_key_path = pathexpand(var.ssh_public_key_path)
  })
  file_permission = "0644"
}
