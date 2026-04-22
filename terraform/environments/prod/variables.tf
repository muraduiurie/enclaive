# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

variable "cluster_name" {
  description = "Cluster identifier prefix for all VMs"
  type        = string
}

variable "box_name" {
  description = "Vagrant box"
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
  type = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to inject into VMs"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to the corresponding SSH private key for Ansible"
  type        = string
}
