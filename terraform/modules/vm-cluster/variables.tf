# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

variable "cluster_name" {
  description = "Prefix used for all VM names (e.g. enclaive-dev)"
  type        = string
}

variable "box_name" {
  description = "Vagrant box to use for all nodes"
  type        = string
  default     = "generic/ubuntu2204"
}

variable "box_version" {
  description = "Pinned Vagrant box version (empty string = latest)"
  type        = string
  default     = ""
}

variable "control_plane_count" {
  description = "Number of control-plane nodes (k3s supports 1 or 3+)"
  type        = number
  default     = 1
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}

variable "control_plane_cpus" {
  description = "vCPUs allocated to each control-plane node"
  type        = number
  default     = 2
}

variable "control_plane_memory_mb" {
  description = "RAM in MB for each control-plane node"
  type        = number
  default     = 2048
}

variable "worker_cpus" {
  description = "vCPUs allocated to each worker node"
  type        = number
  default     = 2
}

variable "worker_memory_mb" {
  description = "RAM in MB for each worker node"
  type        = number
  default     = 2048
}

variable "private_network_prefix" {
  description = "First three octets of the cluster network (e.g. 192.168.56). Control-plane gets .10, workers .11+. Configured on the QEMU multicast interface inside each VM."
  type        = string
  default     = "192.168.56"
}

variable "mcast_port" {
  description = "UDP port for the QEMU socket multicast cluster network. Must be unique per environment so dev and prod can run simultaneously (e.g. dev=4567, prod=4568)."
  type        = number
  default     = 4567
}

variable "ssh_port_base" {
  description = "Starting host port for SSH forwarding. Each node gets base+N. Must not overlap between environments (e.g. dev=50010, prod=50020)."
  type        = number
  default     = 50010
}


variable "vagrantfile_dir" {
  description = "Absolute path to the directory where the rendered Vagrantfile will be written"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to inject into VM authorized_keys"
  type        = string
  default     = "~/.ssh/id_rsa.pub"
}
