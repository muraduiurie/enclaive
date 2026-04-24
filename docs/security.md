# Security

## Secret Management

### Current State (Assessment)

Secrets are committed to git as Kubernetes `Secret` objects with base64-encoded values. This is acceptable for a local demo assessment but is **not production-ready**.

Secrets committed:
- `minio-credentials` (MinIO root user/password, barman S3 keys)
- `pg-app-credentials` (PostgreSQL `app` role password)
- `demo-app-db` (DATABASE_URL including password)
- Argo CD admin password (set by Helm values)

### Production Secret Management

Replace committed secrets with [External Secrets Operator](https://external-secrets.io/) (ESO) + a secrets backend:

```
Vault / AWS Secrets Manager / GCP Secret Manager
         │
External Secrets Operator (in-cluster controller)
         │
ExternalSecret CR (in git, references the external path)
         │  sync
Kubernetes Secret (ephemeral, not in git)
```

With ESO, only the `ExternalSecret` CR goes in git — the actual values never touch the repository:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: pg-app-credentials
  namespace: postgres
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: pg-app-credentials
  data:
    - secretKey: password
      remoteRef:
        key: enclaive/postgres
        property: app_password
```

For CloudNativePG specifically, the operator supports referencing a Vault secret directly via the `bootstrap.initdb.secret` field — no need to pre-create the Secret.

### Secret Rotation

CloudNativePG supports password rotation without downtime:
1. Update the `pg-app-credentials` Secret with the new password
2. CloudNativePG detects the change and runs `ALTER ROLE app PASSWORD '...'`
3. Update `demo-app-db` Secret with the new DATABASE_URL
4. Demo-app deployment rolls (or reconnects on next pool acquisition)

---

## Access Control

### Kubernetes RBAC

k3s installs with RBAC enabled by default. Current service accounts:
- `cloudnative-pg` SA in `cnpg-system` — ClusterRole with CRD access
- `argocd-application-controller` SA — ClusterRole with full resource access (required for GitOps)
- Application pods run as non-root (`runAsUser: 65532`)

Production hardening:
- Scope Argo CD's ClusterRole to specific resource types (not `*`)
- Use separate ServiceAccounts per application with least-privilege Roles
- Enable Kubernetes audit logging and ship to a SIEM

### Network Policies

NetworkPolicies are deployed in the `postgres` and `demo-app` namespaces via
`gitops/applications/postgres/network-policy.yaml` and
`gitops/applications/demo-app/network-policy.yaml`.

Both namespaces follow a **default-deny-all** baseline with additive allow rules.

#### postgres namespace

| Policy | Direction | Selector | Port |
|---|---|---|---|
| `default-deny-all` | Ingress + Egress | all pods | — |
| `allow-demo-app-ingress` | Ingress | `cnpg.io/cluster: pg-cluster` ← `demo-app/app: demo-app` | 5432 |
| `allow-prometheus-scrape` | Ingress | `cnpg.io/cluster: pg-cluster` ← `monitoring` namespace | 9187 |
| `allow-postgres-replication` | Ingress + Egress | pg-cluster pods ↔ pg-cluster pods | 5432 |
| `allow-barman-to-minio` | Egress | `cnpg.io/cluster: pg-cluster` → `app: minio` | 9000 |
| `allow-dns-egress` | Egress | all pods → kube-system | 53/UDP+TCP |

#### demo-app namespace

| Policy | Direction | Selector | Port |
|---|---|---|---|
| `default-deny-all` | Ingress + Egress | all pods | — |
| `allow-http-ingress` | Ingress | `app: demo-app` ← any | 8080 |
| `allow-postgres-egress` | Egress | `app: demo-app` → postgres namespace | 5432 |
| `allow-dns-egress` | Egress | all pods → kube-system | 53/UDP+TCP |

#### What is not yet restricted

- Argo CD, ingress-nginx, and monitoring namespaces do not have NetworkPolicies — they are
  infrastructure components with broader connectivity requirements (GitHub, node metrics,
  cross-namespace service discovery). In production, add deny-all + allow rules per component.
- Egress to the Kubernetes API server (port 6443) is not explicitly allowed in the app
  namespaces — pods that do not need API access inherit the default-deny, which is correct.

### Cluster Access

The kubeconfig (`ansible/kubeconfig/dev.yaml`) grants cluster-admin. In production:
- Distribute per-user kubeconfigs with scoped RBAC roles
- Integrate with SSO (Dex, OIDC) for Argo CD UI access
- Rotate the k3s bootstrap token after cluster join

---

## Network Security

### Firewall (UFW)

Each VM runs UFW with rules managed by the Ansible `security` role:
- Default: `deny incoming`, `allow outgoing`, `allow routed` (CNI requirement)
- SSH: `allow from 127.0.0.1` (QEMU NAT only — no public SSH exposure)
- Kubernetes API: port 6443 open
- NodePort range: 30000-32767 open (for Argo CD, Grafana, demo-app NodePort services)

Production: restrict NodePort range ingress to a load balancer or VPN IP only. Use an ingress controller with TLS termination instead of NodePort.

### TLS

- k3s API server: TLS with self-signed cert, SAN includes 10.0.2.2 and 127.0.0.1
- Argo CD: self-signed TLS on port 443 (production: cert-manager + Let's Encrypt)
- CloudNativePG client connections: `sslmode=disable` in the demo DATABASE_URL (in-cluster, same node)

Production: Enable `sslmode=require` or `verify-full` for all PG connections. CloudNativePG can generate client certificates via cert-manager.

### Ingress

ingress-nginx is deployed but no Ingress objects are defined in this assessment. Services are exposed via NodePort for simplicity.

Production flow:
```
Internet → Load Balancer → ingress-nginx → Service (ClusterIP) → Pod
```
With TLS termination at ingress-nginx using Let's Encrypt certificates issued by cert-manager.

---

## Runtime Security

### Container Security Context

The demo-app Deployment uses:
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 65532          # distroless nonroot UID
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
seccompProfile:
  type: RuntimeDefault
```

CloudNativePG instance pods run as the `postgres` user (UID 26) — set by the operator.

Production additions:
- Pod Security Standards: `enforce: restricted` on all application namespaces
- Falco for runtime anomaly detection (unexpected process execution, file writes)
- Container image scanning in CI (Trivy, Grype) as a blocking step

### Image Supply Chain

- Base image: `gcr.io/distroless/static:nonroot` — no shell, no package manager, minimal CVE surface
- Go binary: statically compiled (`CGO_ENABLED=0`), stripped (`-ldflags="-s -w"`)
- CI: GitHub Actions builds on ubuntu-latest runner with pinned Action versions (`@v4`, `@v5`)

Production additions:
- Sign images with Sigstore Cosign
- Verify signatures in Argo CD via the `argocd-image-updater` + Cosign policy
- Pin all GitHub Action versions to full SHAs instead of tags (`@v4` → `@sha256:...`)
- SBOM generation (Syft) as part of CI, attached to image manifest

### Dependency Management

- Go module: `go.sum` committed — all dependency hashes pinned
- Helm chart versions: pinned in `Chart.yaml` (e.g., `cloudnative-pg: "0.23.0"`)
- `targetRevision: main` in Argo CD Applications — in production, pin to a git tag or SHA
