# enclaive-platform-challenge

A GitOps-based infrastructure platform that provisions a Kubernetes cluster and deploys an operator-managed stateful service. Built as a hiring assessment for the Enclaive Lead Infrastructure Engineer role.

> **NOTICE:** This code is provided solely for the purpose of completing a hiring assessment.
> Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
> is strictly prohibited and gives legal ground if abused.

---

## What this repo does

| Layer | Tool | Purpose |
|---|---|---|
| Infrastructure provisioning | Terraform + Vagrant + QEMU | Spin up 3 local VMs on Apple Silicon |
| Node configuration | Ansible + k3s | Install containerd, bootstrap Kubernetes |
| GitOps | Argo CD | Declarative app delivery, environment separation |
| DB operator | CloudNativePG | Operator-managed 3-node PostgreSQL cluster |
| Monitoring | kube-prometheus-stack | Prometheus + Grafana + PodMonitor |
| Backup | MinIO | S3-compatible local backup target for barman |
| Demo app | Go REST API | Containerized app with CRUD to PostgreSQL |
| CI | GitHub Actions | Builds and pushes demo-app image to ghcr.io |

---

## Repository structure

```
.
├── demo-app/                    # Go REST API source + Dockerfile
│   ├── main.go                  # /healthz + /items CRUD (stdlib HTTP + lib/pq)
│   ├── go.mod / go.sum
│   └── Dockerfile               # multi-stage → distroless/static:nonroot
├── terraform/
│   ├── modules/
│   │   ├── vm-cluster/          # Renders Vagrantfile from template
│   │   └── vagrant-lifecycle/   # Runs vagrant up/destroy, generates Ansible inventory
│   └── environments/
│       ├── dev/                 # 2 vCPU / 2 GB, 192.168.56.x, SSH ports 50010–50012
│       └── prod/                # 4 vCPU / 4 GB, 192.168.57.x, SSH ports 50020–50022
├── ansible/
│   ├── roles/
│   │   ├── base/                # apt, kernel modules, sysctl
│   │   ├── kubernetes/          # containerd, k3s server/agent, QEMU networking fixes
│   │   ├── security/            # UFW, fail2ban, SSH hardening
│   │   └── argocd/              # Helm install + root App-of-Apps bootstrap
│   └── playbooks/
│       └── bootstrap.yml        # 6 plays: base → security → k3s → Argo CD
├── gitops/
│   ├── clusters/dev/            # Argo CD App-of-Apps (one file per child app)
│   ├── infrastructure/
│   │   ├── argocd/              # Argo CD self-managed chart
│   │   ├── ingress-nginx/       # Ingress controller
│   │   └── kube-prometheus-stack/ # Prometheus + Grafana
│   ├── operators/
│   │   └── postgres/            # CloudNativePG operator Helm chart
│   └── applications/
│       ├── postgres/            # Cluster CR, MinIO, ScheduledBackup, PodMonitor
│       └── demo-app/            # Deployment, Service, db-secret
├── docs/
│   ├── architecture.md          # Infrastructure layout, GitOps flow, networking
│   ├── operations.md            # Backup/restore, upgrades, monitoring, scaling
│   ├── security.md              # Secrets, access control, network, runtime, supply chain
│   └── leadership.md            # Team org, multi-env, reliability, security answers
├── .github/workflows/
│   └── demo-app.yml             # CI: build arm64 image → ghcr.io on push to main
├── CLAUDE.md                    # AI agent working context
└── NOTICE                       # Legal notice
```

---

## Known constraints — Apple Silicon (ARM64) networking

On Apple Silicon Macs, QEMU's VM-to-VM networking options are restricted without root privileges:

| Option | Status | Reason |
|---|---|---|
| VirtualBox private_network | Not available | VirtualBox cannot run VMs on ARM64 |
| QEMU socket multicast | Not functional | macOS does not route multicast between user-space QEMU processes |
| QEMU vmnet-host | Requires root | Homebrew QEMU lacks the `com.apple.vm.networking` entitlement |

**Implemented workaround** — k3s joins via QEMU NAT gateway (10.0.2.2). All workloads pinned to cp-0 via `nodeSelector` because flannel VXLAN cannot route cross-node (all VMs share the same VTEP IP 10.0.2.15). Full details in [`docs/architecture.md`](docs/architecture.md) and `CLAUDE.md`.

---

## Infrastructure deployment

### Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Vagrant | 2.3+ | `brew install vagrant` |
| vagrant-qemu plugin | latest | `vagrant plugin install vagrant-qemu` |
| QEMU | 8+ | `brew install qemu` |
| Terraform | 1.5+ | `brew install terraform` |
| Ansible | 2.14+ | `brew install ansible` |

### Step 1 — Provision VMs

```bash
cd terraform/environments/dev
terraform init && terraform apply
```

Creates 3 QEMU ARM64 VMs and writes `ansible/inventory/enclaive-dev.ini`.

### Step 2 — Bootstrap Kubernetes

```bash
cd ansible
ansible-playbook -i inventory/enclaive-dev.ini playbooks/bootstrap.yml
```

Runs 4 plays: `base` → `security` → `k3s server (cp-0)` → `k3s agents (workers)`.
Installs k3s v1.32.4+k3s1, all 3 nodes join and show `Ready`.

Verify:
```bash
kubectl --kubeconfig ansible/kubeconfig/dev.yaml get nodes
```

### Step 3 — Bootstrap Argo CD

```bash
ansible-playbook -i inventory/enclaive-dev.ini playbooks/bootstrap.yml --tags argocd
```

- Opens NodePort range (30000-32767) in UFW
- Installs Argo CD via Helm (all pods pinned to cp-0)
- Applies `gitops/clusters/dev/root-app.yaml` (App-of-Apps)

Argo CD UI:
```bash
kubectl port-forward svc/argocd-server -n argocd 8443:443
# https://localhost:8443  admin / sJWFx4uwVVkdr6eh
```

### Step 4 — Argo CD syncs the platform

Argo CD reads `gitops/clusters/dev/` and creates child Applications:

| Application | Namespace | What |
|---|---|---|
| `ingress-nginx` | ingress-nginx | Ingress controller |
| `kube-prometheus-stack` | monitoring | Prometheus + Grafana |
| `cloudnative-pg` | cnpg-system | CloudNativePG operator |
| `postgres-cluster` | postgres | 3-node PG cluster + MinIO + backups |
| `demo-app` | demo-app | Go REST API |

Wait for the CloudNativePG cluster to reach healthy state (takes ~2-3 min after the operator is running):
```bash
kubectl --kubeconfig ansible/kubeconfig/dev.yaml get cluster -n postgres pg-cluster -w
# NAME         AGE   INSTANCES   READY   STATUS                     PRIMARY
# pg-cluster   2m    3           3       Cluster in healthy state   pg-cluster-1
```

### Step 5 — Build and deploy demo-app

GitHub Actions builds the image on push to `main`. Make the ghcr.io package public:
- GitHub → your profile → Packages → `demo-app` → Package settings → Public

Then the Argo CD `demo-app` Application will sync and the pod will start.

Test:
```bash
# Health check
curl http://127.0.0.1:30080/healthz
# {"status":"ok"}

# Create an item
curl -X POST http://127.0.0.1:30080/items \
  -H 'Content-Type: application/json' \
  -d '{"name":"hello enclaive"}'
# {"id":1,"name":"hello enclaive","created_at":"..."}

# List items
curl http://127.0.0.1:30080/items
```

---

## Timetable

Approximate time spent per area, including debugging QEMU networking issues.

| Task | Time |
|---|---|
| Terraform modules (vm-cluster, vagrant-lifecycle) | 1.5 h |
| Vagrant + QEMU ARM64 debugging (NIC, SSH, networking) | 2.0 h |
| Ansible roles (base, security, kubernetes) | 1.5 h |
| QEMU k3s networking fixes (5 distinct problems) | 3.5 h |
| Ansible Argo CD role + bootstrap | 1.0 h |
| GitOps repo structure + App-of-Apps manifests | 1.0 h |
| Argo CD sync debugging (repo URL, nodeSelector, CRD size) | 1.5 h |
| CloudNativePG manifests (Cluster CR, MinIO, backups) | 1.0 h |
| CloudNativePG bring-up debugging (CRD, webhook, OOM) | 2.0 h |
| Demo app (Go REST API + Dockerfile + CI workflow) | 1.0 h |
| Documentation (architecture, operations, security, leadership) | 1.5 h |
| **Total** | **~18 h** |

The majority of unplanned time was spent on QEMU Apple Silicon networking constraints — multicast ARP broken between VMs, asymmetric routing on the k8sfwd NIC, flannel VXLAN VTEP collision — none of which appear in standard k3s documentation. These are documented in detail in `CLAUDE.md` and `docs/architecture.md`.

---

## Tearing down

```bash
cd terraform/environments/dev
terraform destroy
```

The destroy provisioner calls `vagrant destroy -f` automatically.

---

## LLM conduct

This repository was built with Claude Code (Anthropic) as a development assistant. LLM assistance is noted inline where non-trivial design decisions were made (search for `# LLM note:` in source files). The human author reviewed and validated all generated code before committing.
