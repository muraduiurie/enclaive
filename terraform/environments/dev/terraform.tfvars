# NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
# Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
# is strictly prohibited and gives legal ground if abused.

cluster_name = "enclaive-dev"

# ARM64 box for vagrant-qemu on Apple Silicon.
# On x86 hosts, replace with "generic/ubuntu2204" and set provider to "virtualbox".
box_name    = "perk/ubuntu-2204-arm64"
box_version = ""

# Node topology
control_plane_count     = 1
worker_count            = 2

# Resource allocation (keep low for local dev)
control_plane_cpus      = 2
control_plane_memory_mb = 2048
worker_cpus             = 2
worker_memory_mb        = 2048

# Cluster network — configured on the QEMU multicast interface inside VMs
private_network_prefix = "192.168.56"

# QEMU multicast port (unique per environment: dev=4567, prod=4568)
mcast_port = 4567

# SSH port base — cp-0=50010, worker-0=50011, worker-1=50012
# prod uses 50020+ to avoid overlap
ssh_port_base = 50010

# SSH keys
ssh_public_key_path  = "~/.ssh/id_rsa.pub"
ssh_private_key_path = "~/.ssh/id_rsa"
