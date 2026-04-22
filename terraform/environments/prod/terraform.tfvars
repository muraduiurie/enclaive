# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

cluster_name = "enclaive-prod"

box_name    = "perk/ubuntu-2204-arm64"
box_version = ""

control_plane_count     = 1
worker_count            = 2

control_plane_cpus      = 4
control_plane_memory_mb = 4096
worker_cpus             = 4
worker_memory_mb        = 4096

# Different subnet and multicast port from dev — both can run simultaneously
private_network_prefix = "192.168.57"
mcast_port             = 4568
ssh_port_base          = 50020

ssh_public_key_path  = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
