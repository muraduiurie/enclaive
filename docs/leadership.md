# Leadership

Answers to the four leadership questions from the assessment.

---

## 1. Team Organization

**Context**: 3 DevOps engineers responsible for this platform.

### Roles

I organize by domain ownership — not rotation. Each engineer owns an area of the system
long-term and is expected to go deep. Ownership means being the primary point of contact
for incidents, driving improvements, and being accountable for the quality of work in that
domain.

| Domain | Primary Owner | Backup |
|---|---|---|
| Platform / Kubernetes | Engineer A | Engineer B |
| Databases / Operators | Engineer B | Engineer C |
| CI/CD / Developer Experience | Engineer C | Engineer A |

Knowledge silos are prevented not by rotation but by a strict expectation that the domain
owner documents extensively and shares context proactively. If only one person understands
a system, that is a documentation failure, not an org-chart problem.

### Review Process

**All infrastructure changes go through git.** No one applies kubectl or Terraform manually
in production.

- Branch protection: require 1 approval + passing CI before merge to `main`
- Any engineer can approve any PR — no domain gatekeeping; flat review model
- Terraform: CI pipeline runs `terraform plan` automatically and posts the output to the PR
  as a comment; the reviewer reads the diff, they do not run it manually
- Argo CD `selfHeal: true` corrects drift automatically, reinforcing git as the single source
  of truth

### Release Management

**Environments**: `dev` (automated sync from `main`) → `prod` (human decision, always).

Promotion flow:
1. Change merged to `main` → Argo CD applies to `dev` automatically
2. Engineer validates in `dev` (smoke test, metric check)
3. PR opened from `main` → `prod` with changelog
4. A second engineer must review and approve — no exceptions, including hotfixes
5. Argo CD applies to `prod`

Prod always requires a second pair of eyes. This is a hard rule, not a guideline.

Argo CD sync wave annotations (`argocd.argoproj.io/sync-wave`) control ordering when
multiple changes must sequence (e.g., CRD before CR, operator before cluster CR).

---

## 2. Multi-Environment Deployments

### Environment Separation

The repository uses an **App-of-Apps per environment** pattern:

```
gitops/clusters/dev/   ← Argo CD reads this for the dev cluster
gitops/clusters/prod/  ← Argo CD reads this for the prod cluster
```

Each environment points at the same infrastructure/operator charts with environment-specific
`valueFiles`. Shared defaults live in `values.yaml`; overrides in `values-dev.yaml` /
`values-prod.yaml`.

### Customer Onboarding

Customer onboarding is self-service. A new customer submits their configuration via a
defined interface (PR, form-to-PR pipeline, or CLI tool). CI validates the config with
hardened gates before anything merges — schema validation, policy checks, dry-run apply.
The infra team is not in the critical path for routine onboarding.

Argo CD `ApplicationSet` with a `git` generator automatically creates one Application
per customer directory. Adding a customer is a single validated git commit.

### Upgrade Strategy

**Upgrade decisions are owned by the Product Owner**, not the infra team. The infra team
executes, it does not self-initiate upgrades. The flow:

1. PO opens a ticket with the target version and rationale
2. Engineer picks up the ticket, bumps the chart/image version in a branch
3. CI validates, deploys to `dev`, engineer smoke-tests
4. PO approves promotion; second engineer reviews the prod PR
5. Merge → Argo CD applies to prod

**PostgreSQL minor upgrades**: CloudNativePG handles these via rolling restart. The GitOps
change is a version bump in the Cluster CR; the operator sequences the restart with no
scheduled downtime.

**PostgreSQL major versions**: New cluster bootstrapped from a logical backup
(`bootstrap.recovery`), dual-run period, then DNS/service cutover. Declared in git as a
new Cluster CR — not an in-place upgrade.

**Kubernetes (k3s)**: System Upgrade Controller with a `Plan` CR, draining worker nodes
one at a time, control-plane last.

---

## 3. Reliability

### Repeatable Deployments

The stack is fully declarative:
- Terraform creates VMs from a fixed image with reproducible sizing
- Ansible is idempotent — running `bootstrap.yml` twice produces the same state
- k3s version is pinned (`v1.32.4+k3s1`)
- All Helm chart versions are pinned
- Container image tags point to immutable SHAs in production

Full rebuild procedure: `terraform destroy && terraform apply && ansible-playbook bootstrap.yml`.
All persistent state lives in PostgreSQL (managed, backed up) and MinIO (backed up).
Kubernetes control-plane state is transient — Argo CD regenerates it from git.

### Automated Testing — Priority Order

Testing priority is driven by data reliability first:

| Priority | Layer | What it tests |
|---|---|---|
| 1 | **Database failover** | Insert rows → delete primary pod → wait for failover → verify rows readable from new primary |
| 2 | **Backup restore** | Scheduled job restores from MinIO to a throwaway namespace → verifies row count. A backup never tested is not a backup. |
| 3 | **Smoke test** | POST /items → GET /items against dev after every merge to `main` |
| 4 | Terraform | `terraform validate` + `tflint` in CI |
| 5 | Ansible | `ansible-lint` |
| 6 | Kubernetes manifests | `kubeconform` schema validation in CI |

### Safe Infrastructure Changes — Runbook

Engineers follow runbooks, not checklists. The prod change runbook:

1. Make the change in git, never directly in the cluster
2. Apply to `dev`; validate with the smoke test and metric check
3. Verify Argo CD app health is green before opening the prod PR
4. For destructive changes (PVC resize, major upgrades): take a manual backup first,
   communicate a maintenance window, document the rollback procedure in the ticket
5. Use Argo CD sync waves to sequence dependencies
6. For database schema migrations: `argocd.argoproj.io/hook: PreSync` job runs migrations
   before the new application version starts

**Rollback policy**: roll back first, investigate after. Restore service under no pressure,
then diagnose with a clear head. A git revert → Argo CD sync restores the previous
application state. For stateful services, application rollback does not roll back data —
that requires a restore from backup, which is why tested backups are the first reliability
priority.

---

## 4. Security

### Network

- **Namespaces as security boundaries**: each service tier in its own namespace
- **NetworkPolicy**: default-deny in every namespace, explicit allow for required paths
  (demo-app → postgres:5432, Prometheus → pod metrics endpoints)
- **Ingress TLS**: terminate at ingress-nginx; no plaintext traffic from outside the cluster
- **mTLS**: service mesh (Linkerd or Cilium) for zero-trust pod-to-pod encryption is the
  target architecture for production; not in scope for this assessment but structurally
  compatible

### Data

- **Encryption at rest**: LUKS on VM disks for local deployments; cloud-provider disk
  encryption in production
- **Encryption in transit**: PostgreSQL SSL, MinIO with TLS
- **Backups**: barman archives to MinIO; production target is AWS SSE-KMS for backup
  encryption at rest
- **Sensitive fields**: application-level encryption for PII via `pgcrypto` or a
  KMS-backed key — not in this demo but the pattern is established

### Runtime

- All application containers: `runAsNonRoot`, `readOnlyRootFilesystem`, `drop: [ALL]`
  capabilities, `seccompProfile: RuntimeDefault`
- CloudNativePG sets security context on instance pods per CIS benchmark automatically
- Pod Security Standards: `enforce: restricted` on `demo-app` and `postgres` namespaces
- Image scanning (Trivy) in GitHub Actions CI — non-blocking warning in dev, blocking gate
  in production

### Secrets and Access

- **Vault** as the secrets backend (production experience); External Secrets Operator syncs
  to Kubernetes Secrets
- **OIDC-based cluster access** is the target state — individual identities with time-limited
  tokens, no shared kubeconfig files. Implementation details need reviewing against current
  best practices before applying to a new environment.
- **Principle of least privilege**: applications use dedicated ServiceAccounts with minimal
  permissions; no application uses the `default` SA
- **Audit trail**: Kubernetes audit log + Argo CD audit log → centralized logging (Loki);
  every sync, exec, and manual override is traceable

### Supply Chain

- **Image signing**: Cosign signatures verified by admission policy (production experience)
- **GitHub Actions**: all third-party actions pinned to full commit SHAs, not mutable tags
  (production experience)
- **Go dependencies**: pinned in `go.sum`; `govulncheck` is the target addition to CI
- **Helm chart versions**: pinned; chart sources verified against OCI digest
