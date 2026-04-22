# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

variable "vagrantfile_dir" {
  description = "Absolute path to the directory containing the rendered Vagrantfile"
  type        = string
}

variable "vagrantfile_sha256" {
  description = "Hash of the Vagrantfile content — triggers re-provision when config changes"
  type        = string
}

variable "cluster_name" {
  description = "Cluster name — used as label in the generated Ansible inventory"
  type        = string
}

variable "ansible_inventory_dir" {
  description = "Directory where the generated Ansible inventory file will be written"
  type        = string
}
