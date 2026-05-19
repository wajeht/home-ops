# CNPG (CloudNativePG)

Postgres-as-CRD for the cluster. Every Postgres-backed app gets its own `Cluster` resource — the operator handles provisioning, failover, scaling, and replication. No more hand-rolled Postgres `Deployment`s per app.

## Why CNPG over the alternatives

| Option        | Pros                                                                                      | Cons                                          |
| ------------- | ----------------------------------------------------------------------------------------- | --------------------------------------------- |
| **CNPG**      | CNCF graduated, native k8s-style (CRDs only, no extra control plane), simple `Cluster` CR | Younger than Zalando                          |
| Zalando       | Most mature; battle-tested at scale                                                       | Heavier; pulls in a bunch of legacy machinery |
| Crunchy PGO   | Enterprise features (TLS automation, pgBouncer)                                           | Heavier RBAC/CR surface                       |
| Bitnami chart | Just a chart, no operator                                                                 | No failover, no clustering, no day-2 ops      |

For a homelab where each app has its own DB, CNPG is the dominant choice (upstream, onedr0p, bjw-s all use it).

## What's installed

```
kubernetes/apps/cnpg-system/cnpg/
├── ks.yaml                        # Flux Kustomization (wait=true, 30m interval)
└── app/
    ├── kustomization.yaml
    ├── namespace.yaml             # cnpg-system
    ├── helmrepository.yaml        # cloudnative-pg.github.io/charts
    └── helmrelease.yaml           # chart cloudnative-pg v0.28.2, operator v1.29.1
```

Operator-only. Per-app `Cluster` resources live alongside each app under `kubernetes/apps/<ns>/<app>/`.

## Notable HelmRelease settings

| Setting                        | Value                     | Why                                                                                         |
| ------------------------------ | ------------------------- | ------------------------------------------------------------------------------------------- |
| `crds.create`                  | `true`                    | Chart installs CRDs; Flux owns lifecycle (`install.crds: Create`, `upgrade: CreateReplace`) |
| `replicaCount`                 | 1                         | Single operator pod — HA on a 2-node cluster isn't worth the noise                          |
| `priorityClassName`            | `system-cluster-critical` | Operator going down stops every Postgres failover                                           |
| `monitoring.podMonitorEnabled` | `false`                   | We don't have kube-prometheus-stack yet; flip on when its CRDs land                         |

## The per-app `Cluster` pattern

When an app needs Postgres, drop a `Cluster` CR alongside its manifests:

```yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: hello-world
  namespace: hello-world
spec:
  instances: 1 # bump to 2 when soapwa gets a data disk
  imageName: ghcr.io/cloudnative-pg/postgresql:17-bookworm
  primaryUpdateStrategy: unsupervised
  storage:
    storageClass: longhorn-db
    size: 5Gi
  monitoring:
    enablePodMonitor: false # set true once kube-prometheus-stack is in
  bootstrap:
    initdb:
      database: hello_world
      owner: hello_world
      secret:
        name: hello-world-postgres-creds # SOPS-encrypted Secret with username/password
  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi
```

CNPG generates a Service named `<cluster-name>-rw` (writes) and `<cluster-name>-ro` (read replicas). The app connects via `hello-world-rw.hello-world.svc.cluster.local:5432`.

## Why `longhorn-db` and not the default `longhorn`

CNPG handles its own replication at the Postgres layer (streaming replication between instances). If we also let Longhorn replicate the PV, every write goes to disk 2× per replica — wasted I/O and duplicated failure domains.

So Postgres PVCs land on `longhorn-db` (`numberOfReplicas: 1`) and CNPG handles redundancy by running multiple `instances` in the `Cluster`.

## Backups: delegated to Volsync, not CNPG

CNPG has its own backup story (`Backup` CR + Barman to S3). We **don't use it** — instead we run Volsync's `ReplicationSource` against the Postgres data PVC, the same as any other stateful app. Reasons:

- One backup tool across the whole cluster (Restic via Volsync → Synology NFS)
- No S3-compatible target on the homelab; standing one up just for CNPG isn't worth it
- Volsync's snapshot-then-backup pattern is consistent with how every other PVC is backed up

Trade-off: we lose CNPG's point-in-time recovery (PITR) for Postgres-only restores. For homelab loss tolerance (last nightly backup), this is fine.

If we ever need PITR later, both can coexist — Volsync for daily disaster recovery, CNPG `Backup` for granular Postgres restores.

## Monitoring (later)

When kube-prometheus-stack lands:

1. Flip `monitoring.podMonitorEnabled: true` in `helmrelease.yaml` — operator emits its own metrics
2. In each `Cluster` CR, flip `monitoring.enablePodMonitor: true` — every Postgres instance emits metrics
3. Drop in the CNPG Grafana dashboard (chart ships one)

## Troubleshooting

### Operator pod CrashLoopBackOff

Almost always a CRD mismatch after upgrade. Check:

```bash
kubectl -n cnpg-system logs deploy/cnpg-cloudnative-pg --tail=30
kubectl get crd clusters.postgresql.cnpg.io -o yaml | grep -A 2 storedVersions
```

`upgrade.crds: CreateReplace` should handle this — if it doesn't, the chart docs have the manual migration path.

### Cluster stuck "Setting up primary"

Usually a PVC binding issue — the operator is waiting for Longhorn to provision the volume. Check:

```bash
kubectl -n <app-ns> get pvc
kubectl -n <app-ns> describe cluster <cluster-name>
```

If the PVC is `Pending`, Longhorn doesn't have capacity or the StorageClass is wrong. Confirm `storageClass: longhorn-db` exists.

### Migration from existing docker-cd Postgres

For an app migrating from docker-cd, dump the source DB and restore into the CNPG `Cluster`:

```bash
# On docker-cd host
docker exec <app>-postgres pg_dump -U <user> <db> > /tmp/dump.sql

# Copy to a workstation, then into the CNPG primary
kubectl cp /tmp/dump.sql <app-ns>/<cluster-name>-1:/tmp/dump.sql
kubectl -n <app-ns> exec -it <cluster-name>-1 -- psql -U postgres -d <db> -f /tmp/dump.sql
```

CNPG's `Cluster` has an `externalClusters` import path for live migrations, but `pg_dump` is simpler for the homelab.

## References

- [CNPG docs](https://cloudnative-pg.io/documentation/)
- [Cluster CRD reference](https://cloudnative-pg.io/documentation/current/cloudnative-pg.v1/)
- [upstream's CNPG HelmRelease](https://github.com/upstream/home-ops/blob/main/kubernetes/kubernetes/apps/cnpg-system/cnpg/app/helmrelease.yaml)
