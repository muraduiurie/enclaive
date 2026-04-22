# Architecture

## Infrastructure Layout

```
macOS Host (Apple Silicon M-series)
└── QEMU + Vagrant (vagrant-qemu provider)
    ├── enclaive-dev-cp-0   192.168.56.10  (2 vCPU, 2GB RAM)  control-plane
    ├── enclaive-dev-worker-0  192.168.56.11  (2 vCPU, 2GB RAM)  worker
    └── enclaive-dev-worker-1  192.168.56.12  (2 vCPU, 2GB RAM)  worker
```

Each VM has two NICs:
- `eth0` (10.0.2.15) — QEMU SLIRP user-mode NAT; provides internet access and inter-VM routing via the host at 10.0.2.2
- `enp0s2` (192.168.56.x) — QEMU socket/multicast NIC; **ARP does not work between VMs on Apple Silicon macOS** (L2 multicast bus broken)
- `enp0s3` (10.0.2.15, cp-0 only) — second SLIRP NIC; enables QEMU `hostfwd tcp:0.0.0.0:6443->:6443` so workers can reach the k3s API

## Kubernetes Cluster

**Distribution**: k3s v1.32.4+k3s1 (lightweight, embeds etcd/kine, no external dependencies)

**Topology**:
- 1 control-plane node running the k3s server
- 2 worker nodes running the k3s agent
- CNI: flannel (bundled with k3s, VXLAN mode)

**QEMU Networking Constraints** (Apple Silicon specific):

| Problem | Root Cause | Fix |
|---|---|---|
| Workers can't reach API server | kube-proxy DNAT'd ClusterIP → 192.168.56.10 (unreachable) | `advertise-address: 10.0.2.2` in k3s server config; kube-proxy DNAT → 10.0.2.2:6443 (SLIRP gateway) |
| Cross-node pod-to-pod broken | flannel VXLAN uses 10.0.2.15 as VTEP for all nodes (same IP) | All workloads pinned to cp-0 via `nodeSelector: kubernetes.io/hostname: enclaive-dev-cp-0` |
| UFW blocks CNI traffic | `default deny (routed)` blocks CNI FORWARD chain | `ufw default allow routed` in security role |
| Workers can't masquerade pod traffic | Pod IPs (10.42.x.x) not reachable from SLIRP | `iptables -t nat POSTROUTING MASQUERADE` for 10.0.2.0/24 on workers |
| k8sfwd NIC asymmetric routing | dhclient on enp0s3 adds default route with higher priority | Remove default route after dhclient; policy routing with conntrack marks |

These constraints are encoded in Ansible roles and documented in `CLAUDE.md`. In production on real hardware or cloud VMs, all of these workarounds are removed — flannel VXLAN works correctly with real L2 or routed networking.

## GitOps Workflow

```
Git (github.com/muraduiurie/enclaive)
         │
         │  push to main
         ▼
Argo CD (running in-cluster on cp-0)
         │
         │  App-of-Apps pattern
         │  gitops/clusters/dev/root-app.yaml
         │
         ├── gitops/clusters/dev/argocd-self.yaml        → gitops/infrastructure/argocd/
         ├── gitops/clusters/dev/ingress-nginx.yaml      → gitops/infrastructure/ingress-nginx/
         ├── gitops/clusters/dev/kube-prometheus-stack.yaml → gitops/infrastructure/kube-prometheus-stack/
         ├── gitops/clusters/dev/cloudnative-pg.yaml     → gitops/operators/postgres/
         ├── gitops/clusters/dev/postgres-cluster.yaml   → gitops/applications/postgres/
         └── gitops/clusters/dev/demo-app.yaml           → gitops/applications/demo-app/
```

**App-of-Apps**: The root `dev-root` Application watches `gitops/clusters/dev/`. Every YAML file there is itself an Argo CD Application. Adding a new application to the platform requires only a new file in that directory — Argo CD picks it up automatically on the next sync.

**Sync policy**: All Applications use `automated: {prune: true, selfHeal: true}`. This means:
- Drift from git is corrected automatically
- Resources deleted from git are pruned from the cluster
- No manual `argocd app sync` needed after a git push

## Cluster Architecture

```
Namespace: argocd
  └── Argo CD (8 pods, all on cp-0)

Namespace: cnpg-system
  └── CloudNativePG Operator (1 pod, cp-0)

Namespace: postgres
  ├── MinIO (Deployment + PVC 5Gi, cp-0)            ← barman backup target
  ├── pg-cluster-1  (primary, PostgreSQL 16.6, 1Gi PVC, cp-0)
  ├── pg-cluster-2  (streaming replica, 1Gi PVC, cp-0)
  └── pg-cluster-3  (streaming replica, 1Gi PVC, cp-0)

Namespace: monitoring
  ├── Prometheus (1 pod, cp-0, 10Gi PVC)
  ├── Grafana (1 pod, cp-0, 2Gi PVC)
  ├── Alertmanager (cp-0)
  ├── kube-state-metrics (cp-0)
  └── node-exporter (DaemonSet, all nodes)

Namespace: ingress-nginx
  └── ingress-nginx controller (cp-0)

Namespace: demo-app
  └── demo-app (Go REST API, cp-0)
```

## Storage

All PVCs use the `local-path` StorageClass bundled with k3s. Local-path provisions `hostPath` volumes on the node where the pod is scheduled. Since all workloads are pinned to cp-0, all data lives on cp-0's disk (`/var/lib/rancher/k3s/storage/`).

In production, a distributed StorageClass (Rook/Ceph, Longhorn, or cloud block storage) would be used with replication factor ≥ 2.

## GitOps Deployment Order

1. `terraform apply` — provisions 3 QEMU VMs
2. `ansible-playbook bootstrap.yml` — installs k3s (3 nodes), bootstraps Argo CD, applies root App-of-Apps
3. Argo CD syncs child Applications (operators before applications, by eventual consistency retry)
4. CloudNativePG operator installs CRDs, starts webhook
5. `postgres-cluster` Application creates Cluster CR → operator bootstraps 3-node PG cluster
6. GitHub Actions builds demo-app image → Argo CD syncs Deployment with new image

## CI/CD Pipeline

```
git push to main
    │
    ├─► GitHub Actions (.github/workflows/demo-app.yml)
    │       builds linux/arm64 image
    │       pushes ghcr.io/muraduiurie/demo-app:main + :sha
    │
    └─► Argo CD (polls every 3 minutes)
            detects new manifests
            applies diff to cluster
```

For image promotion in production, Argo CD Image Updater would watch `ghcr.io/muraduiurie/demo-app` for new tags matching a semver pattern, commit the updated image tag back to git, and trigger a sync — keeping the git repository as the single source of truth.
