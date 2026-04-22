# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

variable "cluster_name" {
  description = "Cluster identifier prefix for all VMs"
  type        = string
}

variable "box_name" {
  description = "Vagrant box (must be ARM64-compatible for Apple Silicon hosts)"
  type        = string
}

variable "box_version" {
  description = "Pinned box version (empty = latest)"
  type        = string
  default     = ""
}

variable "control_plane_count" {
  type    = number
  default = 1
}

variable "worker_count" {
  type = number
}

variable "control_plane_cpus" {
  type = number
}

variable "control_plane_memory_mb" {
  type = number
}

variable "worker_cpus" {
  type = number
}

variable "worker_memory_mb" {
  type = number
}

variable "private_network_prefix" {
  description = "First three octets of the cluster network. Configured on the QEMU multicast interface inside each VM."
  type        = string
}

variable "mcast_port" {
  description = "UDP port for QEMU socket multicast cluster network. Must differ between environments."
  type        = number
}

variable "ssh_port_base" {
  description = "Starting host SSH port. Each node gets base+N. Must not overlap between environments."
  type        = number
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key injected into VM authorized_keys"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key for Ansible (kept for documentation; actual key path comes from vagrant ssh-config)"
  type        = string
}
