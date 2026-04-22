# Enclaive Lead Infrastructure Engineer – Home Challenge

## Project Overview

This is a technical assessment for the Enclaive Lead Infrastructure Engineer role.
The goal is to build a **GitOps-based infrastructure platform** capable of deploying a
Kubernetes environment with an operator-managed stateful service.

**Delivery**: GitHub repository with code, README, timetable, and leadership answers.

---

## Repository Structure (target)

```
enclaive-platform-challenge/
├── README.md
├── terraform/
│   ├── modules/
│   └── environments/
│       ├── dev/
│       └── prod/
├── ansible/
│   ├── roles/
│   │   ├── base/
│   │   ├── kubernetes/
│   │   └── security/
│   └── playbooks/
│       └── bootstrap.yml
├── gitops/
│   ├── clusters/
│   │   ├── dev/
│   │   └── prod/
│   ├── infrastructure/
│   ├── operators/
│   │   └── postgres/
│   └── applications/
│       └── demo-app/
└── docs/
    └── architecture.md
```

---

## Requirements Breakdown

### 1. Infrastructure Provisioning (Terraform)
- **Environment choice**: Local VMs (simplest for demo; no cloud account needed)
  - Alternatives: AWS or Hetzner bare metal
- Minimum: 3 Kubernetes nodes + networking + SSH + firewall
- Must be: modular, environment-separated (dev/prod), reusable modules

### 2. Node Configuration (Ansible)
- Install container runtime (containerd)
- Install Kubernetes — use **k3s** (lightweight, fast bootstrap)
- Configure networking
- Prepare cluster for GitOps
- Playbooks must be: idempotent, modular, reusable

### 3. GitOps Deployment
- Tool: **Argo CD** (preferred)
- Responsibilities: install operators, manage manifests, separate environments

### 4. Operator-Based Stateful Service
- Operator: **CloudNativePG** (recommended)
- Database cluster: 3 PostgreSQL instances + persistent volumes + failover
- Backups: automated to S3 or MinIO, scheduled, with restore procedure
- Monitoring: Prometheus-compatible (ServiceMonitor + exporter)
- Upgrades: PostgreSQL minor upgrades via rolling restart + GitOps change management

### 5. Example Application
- Simple containerized REST API
- Reads/writes to the operator-managed PostgreSQL
- Deployed via GitOps

---

## Documentation Required

### Architecture doc (`docs/architecture.md`)
- Infrastructure layout
- Cluster architecture
- GitOps workflow

### Operational lifecycle
- Database backup/restore
- Upgrades
- Monitoring
- Scaling

### Security considerations
- Secret management
- Access control
- Network policies

---

## Leadership Questions (to answer in repo)

1. **Team Organization** — roles, review process, release management for 3 DevOps engineers
2. **Multi-Environment Deployments** — customer configs, infra variations, upgrade strategy
3. **Reliability** — repeatable deployments, automated testing, safe infra changes
4. **Security** — network, data, runtime, secrets, access, supply chain

---

## Evaluation Criteria

| Category | What's Assessed |
|---|---|
| Infrastructure Engineering | Terraform quality, Ansible automation, repo structure |
| Kubernetes Maturity | Operator usage, stateful workloads, lifecycle management |
| GitOps Thinking | Declarative infra, reproducibility, environment separation |
| Operational Thinking | Backup, monitoring, upgrades |
| Leadership Thinking | Team organization, operational strategy |

---

## Key Decisions / Implementation Notes

- **LLM usage must be documented** (in code comments or a separate LLM conduct doc)
- No prior confidential computing experience required — standard tooling applies
- Partial implementation is acceptable — architecture and quality matter more than completeness

## Tech Stack Choices

| Layer | Tool |
|---|---|
| Infrastructure | Terraform + Vagrant + QEMU (Apple Silicon ARM64) |
| Node config | Ansible + k3s v1.32.4 |
| GitOps | Argo CD |
| DB Operator | CloudNativePG |
| Monitoring | Prometheus + Grafana (kube-prometheus-stack) |
| Backup target | MinIO (self-hosted S3-compatible) |
| Demo app | Simple Go or Python REST API |

---

## Notes for Claude

- Prioritize correctness and architecture clarity over feature completeness
- Document LLM usage inline with `# LLM note:` comments in source files; also noted in README
- README must include a timetable (time per sub-task) — not yet written
- NOTICE header must appear at the top of every new source file created

## Deployment order (authoritative)

Follow this exact order when building or testing the platform end-to-end:

1. `cd terraform/environments/dev && terraform init && terraform apply`
   - Creates 3 QEMU/ARM64 VMs via Vagrant
   - Writes `ansible/inventory/enclaive-dev.ini` (generated from `vagrant ssh-config`)
2. `cd ansible && ansible-playbook -i inventory/enclaive-dev.ini playbooks/bootstrap.yml`
   - Runs 4 plays: `base` (all) → `security` (all) → `kubernetes/server` (cp-0) → `kubernetes/agent` (workers)
   - Installs k3s v1.32.4+k3s1; all 3 nodes join and show Ready
3. `cd ansible && ansible-playbook -i inventory/enclaive-dev.ini playbooks/bootstrap.yml --tags argocd`
   - Opens NodePort range (30000-32767) in UFW on all nodes
   - Installs Argo CD via Helm (all pods pinned to cp-0 — QEMU multicast NIC broken, no cross-node pod traffic)
   - Applies `gitops/clusters/dev/root-app.yaml` (App-of-Apps)
   - UI: `kubectl port-forward svc/argocd-server -n argocd 8443:443` → https://localhost:8443 (admin / sJWFx4uwVVkdr6eh)
4. Argo CD syncs `gitops/clusters/dev/` — installs operators and applications
   - Requires the GitHub repo to exist and code to be pushed first

## What exists vs what is still to be built

| Component | Status |
|---|---|
| `.gitignore` | Done |
| `NOTICE` + per-file headers | Done |
| `README.md` | Done |
| `CLAUDE.md` | Done (this file) |
| `terraform/modules/vm-cluster` | Done |
| `terraform/modules/vagrant-lifecycle` | Done |
| `terraform/environments/dev` | Done |
| `terraform/environments/prod` | Done |
| `ansible/ansible.cfg` | Done |
| `ansible/roles/base` | Done |
| `ansible/roles/kubernetes` | Done |
| `ansible/roles/security` | Done |
| `ansible/playbooks/bootstrap.yml` | Done |
| `ansible/roles/argocd` | Done |
| `gitops/clusters/dev/` (root App-of-Apps + child apps) | Done |
| `gitops/infrastructure/argocd/` | Done |
| `gitops/infrastructure/ingress-nginx/` | Done |
| `gitops/infrastructure/kube-prometheus-stack/` | Done |
| `gitops/operators/postgres/` (CloudNativePG operator chart) | Done |
| `gitops/applications/demo-app/` (namespace placeholder) | **TODO (full app)** |
| GitHub repo push (required for Argo CD to sync) | **TODO** |
| CloudNativePG PostgreSQL Cluster CR | **TODO** |
| Demo app (Go/Python REST API) | **TODO** |
| `docs/architecture.md` | **TODO** |
| `docs/operations.md` | **TODO** |
| `docs/security.md` | **TODO** |
| `docs/leadership.md` | **TODO** |
| README timetable | **TODO** |

## Apple Silicon Networking — Solved Constraints

These are non-obvious problems specific to running QEMU VMs on macOS ARM64.
They are already solved and encoded in the Ansible roles; do not re-litigate them.

### Problem 1 — k8sfwd NIC not forwarding (TLS hangs)
- **Cause**: The second QEMU user NIC (`enp0s3`, the `k8sfwd` NIC) starts DOWN with no IP.
  QEMU's SLIRP accepts TCP connections at host:6443 but can't deliver data to the VM.
- **Fix**: Bring up `enp0s3` with DHCP (SLIRP assigns 10.0.2.15). Add policy routing
  using iptables conntrack marks + fwmark so SYN-ACK replies egress via `enp0s3`
  (not `eth0`), resolving the asymmetric routing problem.
- **Encoded in**: `ansible/roles/kubernetes/tasks/k3s_server.yml`

### Problem 2 — k3s agent proxy tunnel uses cluster IP
- **Cause**: After initial auth via `10.0.2.2:6443`, the k3s server returns its cluster IP
  (`192.168.56.10`) for the remotedialer WebSocket tunnel. Workers cannot reach
  `192.168.56.10` (no VM-to-VM multicast on macOS).
- **Fix**: Workers add an iptables DNAT OUTPUT rule:
  `192.168.56.10:6443 → 10.0.2.2:6443`. Connections route via QEMU NAT → host:6443
  → k8sfwd hostfwd → cp-0:6443.
- **Encoded in**: `ansible/roles/kubernetes/tasks/k3s_agent.yml`

### Problem 3 — QEMU multicast NIC (enp0s2) ARP does not work between VMs
- **Cause**: The QEMU socket/mcast NIC (`enp0s2`, 192.168.56.x) does not deliver ARP between
  VMs on Apple Silicon macOS. ARP shows `(incomplete)` for all peers. Result: no direct
  VM-to-VM L2 or L3 connectivity. flannel VXLAN uses `10.0.2.15` (SLIRP IP) as VTEP for
  all nodes → cross-node pod-to-pod traffic is broken.
- **Fix**: 
  1. `advertise-address: "10.0.2.2"` in k3s server config so the kubernetes Service ClusterIP
     DNAT leads to 10.0.2.2:6443 (reachable via SLIRP) instead of 192.168.56.10:6443.
  2. All workloads pinned to cp-0 via nodeSelector to avoid cross-node pod-to-pod traffic.
  3. UFW `default allow routed` so CNI FORWARD chain isn't blocked.
  4. Workers: MASQUERADE on POSTROUTING for 10.0.2.0/24 so pod traffic reaches SLIRP.
  5. enp0s3 default route removed after dhclient (k8sfwd SLIRP doesn't return internet replies).
- **Encoded in**: `ansible/roles/kubernetes/tasks/k3s_server.yml`, `k3s_agent.yml`,
  `ansible/roles/security/tasks/main.yml`, Argo CD Helm values template
- **Documentation**: Document this constraint in architecture.md

### Problem 4 — unattended-upgrades holds apt lock
- **Cause**: Ubuntu 22.04 starts `unattended-upgrades` shortly after boot, holding
  the dpkg frontend lock for several minutes.
- **Fix**: `systemctl stop unattended-upgrades` at the start of any role that does apt.
- **Encoded in**: `ansible/roles/base/tasks/main.yml` and
  `ansible/roles/kubernetes/tasks/containerd.yml`

## Ansible role key details

### `ansible/roles/kubernetes/defaults/main.yml`
```yaml
k3s_version: "v1.32.4+k3s1"
k3s_api_via_host: "10.0.2.2"      # QEMU NAT gateway — reachable from all VMs
k3s_api_port: 6443
k3s_tls_sans: ["10.0.2.2", "127.0.0.1"]
k3s_cluster_iface: "enp0s2"        # secondary NIC for cluster IP (socket multicast NIC)
```

### bootstrap.yml play ordering
- Play 3 (k3s server on control_plane) sets `k3s_token` via `set_fact`
- Play 4 (k3s agents on workers) reads `hostvars[cp_host]['k3s_token']`
- Both plays MUST run in the same `ansible-playbook` invocation
- Using `--limit workers` alone will fail on the token assert — always run without `--limit`

### k3s cluster IPs
- cp-0: 192.168.56.10, SSH port 50010
- worker-0: 192.168.56.11, SSH port 50011
- worker-1: 192.168.56.12, SSH port 50012
- All VMs SSH via 127.0.0.1 (QEMU NAT hostfwd)
