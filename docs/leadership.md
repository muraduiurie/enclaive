# Leadership

Answers to the four leadership questions from the assessment.

---

## 1. Team Organization

**Context**: 3 DevOps engineers responsible for this platform.

### Roles

Rather than assigning fixed titles, I'd organize by domain ownership with rotation:

| Domain | Primary Owner | Backup |
|---|---|---|
| Platform / Kubernetes | Engineer A | Engineer B |
| Databases / Operators | Engineer B | Engineer C |
| CI/CD / Developer Experience | Engineer C | Engineer A |

Ownership means being on-call for incidents, driving improvements, and being the first reviewer for PRs in that domain. Rotation every 6 months prevents knowledge silos — the person who didn't build the thing eventually maintains it.

### Review Process

**All infrastructure changes go through git.** No one applies kubectl or terraform manually in production. This is enforced by:
- Branch protection: require 1 review + passing CI before merge to `main`
- Argo CD: `selfHeal: true` — drift is corrected automatically, reinforcing that git is truth
- Terraform: `plan` output posted to the PR as a comment; engineer reviews the diff before approving

Review split:
- Terraform changes: peer review + test in dev environment before merging
- Helm values / Argo CD changes: peer review; Argo CD syncs to dev automatically, reviewer checks dev app health before approving prod promotion
- Application manifests: author's domain owner approves; second engineer spot-checks security context, resource limits

### Release Management

**Environments**: `dev` (auto-sync from `main`) → `prod` (manual promotion via PR to a `prod` branch or tag).

Promotion flow:
1. Change merged to `main` → Argo CD applies to `dev` automatically
2. Engineer validates in `dev` (smoke test, metric check)
3. PR opened from `main` → `prod` with changelog
4. Second engineer reviews, approves, merges
5. Argo CD applies to `prod`

Argo CD's sync wave annotations (`argocd.argoproj.io/sync-wave`) control ordering when multiple changes must sequence (e.g., CRD before CR, operator before cluster CR).

---

## 2. Multi-Environment Deployments

### Environment Separation

The repository uses an **App-of-Apps per environment** pattern:

```
gitops/clusters/dev/   ← Argo CD reads this for the dev cluster
gitops/clusters/prod/  ← Argo CD reads this for the prod cluster
```

Each environment has its own set of Argo CD Applications pointing at the same infrastructure/operator charts but with environment-specific `valueFiles`. Shared defaults live in a base `values.yaml`; overrides in `values-dev.yaml` / `values-prod.yaml`.

### Customer Configuration Variations

For a multi-tenant platform where each customer has different infrastructure:

1. **Helm values per customer**: A `values-customer-acme.yaml` layer on top of the base, managed in a separate `customers/` directory or a separate repo (GitOps multi-repo pattern)
2. **ApplicationSet**: Argo CD `ApplicationSet` with a `git` generator can automatically create one Application per directory in `customers/` — adding a new customer is a single git commit
3. **Kustomize overlays**: Base manifests in `gitops/base/`, overlay per environment/customer in `gitops/overlays/acme-prod/`

### Upgrade Strategy

**Operators** (CloudNativePG, etc.): Pin chart version in `Chart.yaml`. Upgrade by bumping the version, testing in dev, then promoting to prod. The operator's own rolling-restart mechanism handles PostgreSQL minor upgrades with zero scheduled downtime.

**Kubernetes** (k3s): k3s supports in-place upgrades via the [System Upgrade Controller](https://github.com/rancher/system-upgrade-controller). A `Plan` CR targets nodes by label, upgrading one at a time. Worker nodes drain before upgrade; control-plane upgrades last.

**PostgreSQL major versions**: New cluster bootstrap from a logical backup, dual-run period with replication, then DNS/service cutover. Declared in git as a new Cluster CR with `bootstrap.recovery`, not an in-place upgrade.

---

## 3. Reliability

### Repeatable Deployments

The stack is fully declarative:
- Terraform creates VMs with a fixed image, fixed sizing, reproducible Vagrant box
- Ansible is idempotent — running `bootstrap.yml` twice produces the same state
- k3s version is pinned (`v1.32.4+k3s1`)
- All Helm chart versions are pinned
- Container image tags point to immutable SHAs in production

Tearing down and rebuilding the full stack: `terraform destroy && terraform apply && ansible-playbook bootstrap.yml`. All state lives in PostgreSQL (managed, backed up) and MinIO (backed up). Kubernetes control-plane state (etcd/kine) is transient — it's regenerated from Argo CD syncing git.

### Automated Testing

Current gap: no automated infrastructure tests. What I'd add:

| Layer | Tool | What it tests |
|---|---|---|
| Terraform | `terraform validate` + `tflint` in CI | syntax, best practices |
| Ansible | `ansible-lint` + Molecule | role correctness, idempotency |
| Kubernetes manifests | `kubeval` / `kubeconform` in CI | manifest schema validity |
| Integration | `pytest` + `kubectl` port-forward | smoke test: POST /items, GET /items |
| Chaos | Chaos Mesh / `kubectl delete pod` script | failover, backup restore |

Specifically for the database: an automated test that (a) inserts rows, (b) deletes the primary pod, (c) waits for failover, (d) verifies the rows are still readable from the new primary — this tests the full HA story.

### Safe Infrastructure Changes

**The change-safely checklist**:
1. Make the change in git, not directly in the cluster
2. Apply to `dev` first; validate with metrics + smoke test
3. Check Argo CD app health before promoting to `prod`
4. For destructive changes (PVC resize, major upgrades): take a manual backup first, communicate a maintenance window, have a rollback plan
5. Use Argo CD sync waves to sequence dependencies
6. For database schema migrations: use a job with `argocd.argoproj.io/hook: PreSync` so migrations run before the new app version starts

**Rollback**: Revert the git commit → Argo CD syncs the previous state. For stateful services (PostgreSQL), a rollback of the application version does not roll back data — that requires a restore from backup.

---

## 4. Security

### Network

- **Namespaces as security boundaries**: each service tier in its own namespace
- **NetworkPolicy**: default-deny in every namespace, explicit allow for required paths (demo-app → postgres:5432, prometheus → pod metrics endpoints)
- **Ingress TLS**: terminate at ingress-nginx with Let's Encrypt; no plaintext traffic from outside the cluster
- **mTLS**: optional overlay with a service mesh (Linkerd, Cilium) for zero-trust pod-to-pod encryption; not in scope for this assessment but architecturally compatible

### Data

- **Encryption at rest**: use LUKS on the VM disk (Vagrant provisioner), or rely on cloud-provider disk encryption in production
- **Encryption in transit**: PostgreSQL SSL (`sslmode=require`), MinIO with TLS
- **Backups**: barman archives encrypted at the MinIO layer (server-side encryption); for production, use AWS SSE-S3 or SSE-KMS
- **Sensitive columns**: application-level encryption for PII fields (not implemented in this demo — would use `pgcrypto` extension or a KMS-backed encryption key)

### Runtime

- All application containers: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]` capabilities, `seccompProfile: RuntimeDefault`
- CloudNativePG instance pods: operator sets security context automatically per CIS benchmark
- Pod Security Standards: `enforce: restricted` on `demo-app` and `postgres` namespaces
- Image scanning (Trivy) in GitHub Actions CI as a non-blocking warning today, blocking gate in production

### Secrets and Access

- **Vault** as the secrets backend; External Secrets Operator syncs to Kubernetes Secrets
- **No static kubeconfig files** shared between engineers; individual OIDC-based identities with time-limited tokens
- **Principle of least privilege**: applications get a ServiceAccount with only the permissions they need; no applications use `default` SA
- **Audit trail**: Kubernetes audit log + Argo CD audit log → centralized SIEM (Loki/Elasticsearch); every `kubectl exec`, every sync, every manual override is traceable

### Supply Chain

- Signed container images (Sigstore Cosign) verified by Argo CD admission policy
- Go dependencies pinned in `go.sum` and scanned with `govulncheck` in CI
- Helm chart versions pinned; chart sources verified against OCI digest
- GitHub Actions pinned to full commit SHAs, not mutable tags
