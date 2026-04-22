# Operations

## Database Backup and Restore

### How Backups Work

CloudNativePG uses [barman-cloud](https://www.pgbarman.org/) to stream WAL archives and take base backups to MinIO (S3-compatible). Two layers:

| Layer | Mechanism | Frequency | Retention |
|---|---|---|---|
| WAL archiving | Continuous streaming to `s3://cnpg-backups/pg-cluster/wals/` | Per-WAL-segment (~16MB) | 7 days |
| Base backup | `ScheduledBackup` CR triggers `pg_basebackup` | Daily at 02:00 UTC | 7 days |

Point-in-time recovery is possible to any second within the 7-day window.

### Taking a Manual Backup

```bash
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: manual-$(date +%Y%m%d)
  namespace: postgres
spec:
  cluster:
    name: pg-cluster
  method: barmanObjectStore
EOF

# Watch progress
kubectl get backup -n postgres -w
```

### Restore Procedure

**Full restore to a new cluster** (disaster recovery):

```bash
# 1. Create a recovery cluster pointing at the same barman store.
#    targetTime is optional — omit for latest consistent state.
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg-cluster-restored
  namespace: postgres
spec:
  instances: 3
  imageName: ghcr.io/cloudnative-pg/postgresql:16.6
  affinity:
    nodeSelector:
      kubernetes.io/hostname: enclaive-dev-cp-0
  storage:
    size: 1Gi
    storageClass: local-path
  bootstrap:
    recovery:
      source: pg-cluster-backup
      # recoveryTarget:
      #   targetTime: "2026-04-22 10:00:00"  # optional PITR
  externalClusters:
    - name: pg-cluster-backup
      barmanObjectStore:
        destinationPath: s3://cnpg-backups/pg-cluster/
        endpointURL: http://minio-svc.postgres.svc:9000
        s3Credentials:
          accessKeyId:
            name: minio-credentials
            key: ACCESS_KEY_ID
          secretAccessKey:
            name: minio-credentials
            key: SECRET_ACCESS_KEY
EOF

# 2. Wait for the restored cluster to reach healthy state
kubectl get cluster pg-cluster-restored -n postgres -w

# 3. Switch the demo-app DATABASE_URL to the restored cluster's rw service
# (update db-secret.yaml in gitops/applications/demo-app/ and push)
```

**Point-in-time recovery**: Add `recoveryTarget.targetTime` to the cluster spec above.

### Verify Backup is Working

```bash
# Check WAL archiving status on the primary
kubectl exec -n postgres pg-cluster-1 -- \
  psql -U postgres -c "SELECT * FROM pg_stat_archiver;"

# List base backups in MinIO
kubectl exec -n postgres deploy/minio -- \
  mc alias set local http://localhost:9000 minio-admin minio-password && \
  kubectl exec -n postgres deploy/minio -- mc ls local/cnpg-backups/pg-cluster/base/

# Check ScheduledBackup status
kubectl get scheduledbackup -n postgres
kubectl get backup -n postgres
```

---

## PostgreSQL Minor Version Upgrades

CloudNativePG handles minor upgrades via a rolling restart — no downtime for reads, brief write interruption during primary switchover.

### Upgrade Steps

1. **Update the image tag** in `gitops/applications/postgres/cluster.yaml`:
   ```yaml
   spec:
     imageName: ghcr.io/cloudnative-pg/postgresql:16.7  # was 16.6
   ```

2. **Commit and push** — Argo CD applies the change to the Cluster CR.

3. **CloudNativePG performs a rolling restart**:
   - Replicas are updated first (one at a time)
   - Primary is switched over to an already-updated replica
   - Old primary restarts on the new image
   - Total writes-unavailable window: typically < 5 seconds

4. **Verify**:
   ```bash
   kubectl get cluster -n postgres pg-cluster
   kubectl get pods -n postgres
   kubectl exec -n postgres pg-cluster-1 -- \
     psql -U postgres -c "SELECT version();"
   ```

### Major Version Upgrades

Major upgrades (e.g., 16 → 17) require `pg_upgrade` and more care:
1. Take a manual backup
2. Create a new cluster with `bootstrap.initdb` on the new major version
3. Logical replication from old → new cluster (or restore from backup)
4. Switch the application connection string
5. Delete the old cluster

---

## Monitoring

### Dashboards

- **Grafana**: `http://<node-ip>:30300` (admin / enclaive-dev)
- **Argo CD UI**: `kubectl port-forward svc/argocd-server -n argocd 8443:443` → https://localhost:8443

### Key Metrics

CloudNativePG exports Prometheus metrics on port 9187 of each instance pod. A `PodMonitor` CR (created automatically by `enablePodMonitor: true` in the Cluster spec) tells Prometheus to scrape them.

Important metrics to alert on:

| Metric | Alert Condition | Meaning |
|---|---|---|
| `cnpg_pg_replication_in_recovery` | != 0 on primary | Primary has restarted as standby |
| `cnpg_pg_replication_lag` | > 30s on any replica | Replica falling behind |
| `cnpg_pg_stat_archiver_failed_count` | > 0 | WAL archiving to MinIO failing |
| `cnpg_pg_database_size_bytes` | > 800Mi | Approaching PVC limit |
| `container_memory_working_set_bytes` | > limit * 0.9 | OOM risk |

### Viewing Metrics

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

### Scaling

**Horizontal (more replicas)**:
```yaml
# gitops/applications/postgres/cluster.yaml
spec:
  instances: 5  # was 3
```
Push → Argo CD applies → CloudNativePG adds replicas online.

**Vertical (more resources)**:
```yaml
spec:
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2
      memory: 2Gi
```
Triggers a rolling restart.

**Storage expansion**:
```yaml
spec:
  storage:
    size: 10Gi  # was 1Gi
```
Supported if the StorageClass allows volume expansion (`local-path` does on most setups).

---

## Incident Runbook

### Primary pod restarted / failover occurred

```bash
# 1. Find the new primary
kubectl get cluster -n postgres pg-cluster -o jsonpath='{.status.currentPrimary}'

# 2. Check cluster events
kubectl describe cluster -n postgres pg-cluster | tail -30

# 3. Check if all replicas re-attached
kubectl get pods -n postgres
```

CloudNativePG handles failover automatically — no manual intervention required.

### WAL archiving failures

```bash
# Check archiver status
kubectl exec -n postgres pg-cluster-1 -- \
  psql -U postgres -c "SELECT last_failed_wal, last_failed_time, last_error FROM pg_stat_archiver;"

# Check MinIO is reachable from the postgres pod
kubectl exec -n postgres pg-cluster-1 -- \
  curl -s http://minio-svc.postgres.svc:9000/minio/health/ready
```

### Demo-app cannot connect to database

```bash
# 1. Check the rw service endpoint
kubectl get endpoints -n postgres pg-cluster-rw

# 2. Test connectivity from demo-app pod
kubectl exec -n demo-app deploy/demo-app -- \
  wget -qO- http://localhost:8080/healthz

# 3. Check the secret value
kubectl get secret -n demo-app demo-app-db -o jsonpath='{.data.DATABASE_URL}' | base64 -d
```
