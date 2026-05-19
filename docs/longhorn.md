# Longhorn

Block storage for the cluster. Every PersistentVolumeClaim that doesn't specify a storage class lands here. Replicated across nodes (when capacity allows), snapshotted, and exposed as the default cluster storage.

## Why Longhorn over the alternatives

| Option                 | Pros                                                                     | Cons                                            |
| ---------------------- | ------------------------------------------------------------------------ | ----------------------------------------------- |
| **Longhorn**           | Pure k8s-native, web UI, snapshots, backups, easy multi-node replication | Some I/O overhead vs raw disk                   |
| Rook-Ceph              | Industrial-strength, S3 + block + filesystem                             | Heavyweight, 3-node minimum for safe quorum     |
| local-path-provisioner | Trivially simple                                                         | No replication, no snapshots — single-node only |
| OpenEBS                | Multiple engines, mature                                                 | More moving parts                               |

For a 2-node homelab, **Longhorn** is the dominant choice (upstream, onedr0p, bjw-s all use it).

## Prerequisites

- Talos cluster with the `iscsi-tools` and `util-linux-tools` system extensions baked in (already in our schematic — see [talos.md](talos.md))
- A dedicated data disk on at least one node — Longhorn refuses to share the OS disk safely
- Flux running (so the HelmRelease lands via GitOps)

## Disk layout

| Node       | Data disk                           | Mount               | Available             |
| ---------- | ----------------------------------- | ------------------- | --------------------- |
| **soapwa** | none (OS-only)                      | —                   | 0 GB (will add later) |
| **yanlon** | `/dev/sda` 1TB SanDisk SDSSDH3 SATA | `/var/mnt/longhorn` | 954 GiB               |

Only yanlon contributes storage today. With 1 disk → `numberOfReplicas: 1`. Volsync handles backups to NAS, so a yanlon failure is recoverable.

When soapwa gets a second disk, bump replicas to 2 (instructions below).

## How Talos mounts the disk

Talos won't let you just shell in and `mount` a disk — it's an immutable OS. Instead, we declare a **UserVolume** in `talconfig.yaml`:

```yaml
nodes:
  - hostname: yanlon
    ...
    patches:
      - |-
        apiVersion: v1alpha1
        kind: UserVolumeConfig
        name: longhorn
        provisioning:
          diskSelector:
            match: disk.transport == "sata"
          minSize: 100GB
        filesystem:
          type: xfs
```

Talos:

1. Selects the first matching disk (SATA on yanlon = the 1TB SanDisk)
2. Creates a partition `u-longhorn` filling it
3. Formats XFS
4. Mounts at `/var/mnt/<name>` → `/var/mnt/longhorn`

The mount survives reboots and Talos upgrades. The disk is owned by the UserVolume — Talos won't touch it from anywhere else.

To verify:

```bash
talosctl --nodes 192.168.4.163 --endpoints 192.168.4.163 \
  --talosconfig kubernetes/talos/clusterconfig/talosconfig \
  get volumestatus | grep longhorn
```

You should see `u-longhorn  partition  ready  /dev/sda1  1.0 TB`.

## Layout

```
kubernetes/apps/longhorn/
├── ks.yaml                          # 2 Flux Kustomizations: app + config (config dependsOn app)
├── app/
│   ├── kustomization.yaml
│   ├── namespace.yaml               # longhorn-system, privileged PSA labels
│   ├── helmrepository.yaml          # charts.longhorn.io
│   └── helmrelease.yaml             # v1.11.1
└── config/
    ├── kustomization.yaml
    └── storageclass.yaml            # `longhorn-db` only (default `longhorn` SC is chart-owned)
```

## Notable HelmRelease settings

| Setting                                | Value                     | Why                                                                |
| -------------------------------------- | ------------------------- | ------------------------------------------------------------------ |
| `defaultDataPath`                      | `/var/mnt/longhorn`       | Matches the Talos UserVolume mount                                 |
| `defaultReplicaCount`                  | 1                         | Only one disk available                                            |
| `priorityClass`                        | `system-cluster-critical` | Longhorn going down breaks every stateful app                      |
| `persistence.defaultClass`             | `true`                    | Chart creates the `longhorn` StorageClass and marks it the default |
| `persistence.defaultClassReplicaCount` | 1                         | Default-class replica count (bump to 2 when soapwa gets a disk)    |
| `persistence.defaultDataLocality`      | `best-effort`             | Schedule replicas near workloads when possible                     |
| `persistence.reclaimPolicy`            | `Delete`                  | PV deleted when PVC is deleted (Volsync handles backup separately) |

## StorageClasses

| Name                     | Source                                  | Replicas     | When to use                                                                                 |
| ------------------------ | --------------------------------------- | ------------ | ------------------------------------------------------------------------------------------- |
| **`longhorn`** (default) | Chart (`persistence.defaultClass=true`) | 1 (target 2) | Any app that wants HA — used when a PVC omits `storageClassName`                            |
| **`longhorn-db`**        | `config/storageclass.yaml`              | 1            | Postgres/databases — CNPG handles replication itself, no need for Longhorn-level redundancy |
| `longhorn-static`        | Chart (always created)                  | n/a          | For manually-managed PVs; we don't use it                                                   |

`longhorn-db` is opt-in (CNPG `Cluster` resources reference it explicitly).

## When you add soapwa's second disk later

1. Power off soapwa, install the new SSD, power back on
2. Add a per-node patch to `talconfig.yaml`:
   ```yaml
   nodes:
     - hostname: soapwa
       ...
       patches:
         - |-
           apiVersion: v1alpha1
           kind: UserVolumeConfig
           name: longhorn
           provisioning:
             diskSelector:
               match: disk.transport == "sata" && !system_disk
             minSize: 100GB
           filesystem:
             type: xfs
   ```
3. `make talos-config && make talos-apply` (live update, no reboot)
4. Verify the volume: `talosctl ... get volumestatus | grep longhorn`
5. Bump `persistence.defaultClassReplicaCount: 1` → `2` in `helmrelease.yaml` (the default `longhorn` SC is chart-owned). Leave `longhorn-db` at 1 — CNPG handles its own replication.
6. Commit + push — Longhorn picks up the new node disk and rebalances existing PVs

The `!system_disk` selector ensures the OS disk on soapwa is not selected.

## Web UI

Longhorn exposes a dashboard at `longhorn-frontend.longhorn-system.svc.cluster.local:80`. To expose it externally:

1. Add a public hostname in Cloudflare Tunnel: `longhorn.wajeht.com → cilium-gateway-internet.kube-system.svc.cluster.local:80`
2. Create an HTTPRoute attaching to the `internet` Gateway, hostname `longhorn.wajeht.com`, backend `longhorn-frontend`
3. **Protect with oauth2-proxy** when we install it — Longhorn UI has no built-in auth

For now, port-forward to access it locally:

```bash
kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80
# → http://localhost:8080
```

## Backup target (later, with Volsync)

Longhorn has its own backup-to-S3 feature, but we use **Volsync** for PVC backups (cleaner GitOps integration). When Volsync is installed, each app's `ReplicationSource` snapshots its PVC and ships the data to Restic on the NAS.

Longhorn's built-in backup target stays unset.

## Troubleshooting

### Pods stuck Pending with "no available storage class"

Default StorageClass annotation missing. Check:

```bash
kubectl get storageclass
# `longhorn` should have (default) suffix
```

### PVCs stuck Pending with "no available replicas"

Disk discovery failed. Check Longhorn's view of the node:

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o yaml | grep -A 5 disks
```

You should see yanlon with `/var/mnt/longhorn` listed as a disk path.

### Longhorn manager pods CrashLoopBackOff

Probably missing iscsi-tools — but our Talos image includes them. Verify:

```bash
talosctl --nodes <node> get extensions
# Should list siderolabs/iscsi-tools and siderolabs/util-linux-tools
```

## References

- [Longhorn docs](https://longhorn.io/docs/)
- [Talos UserVolumes](https://www.talos.dev/v1.12/talos-guides/configuration/disk-management/)
- [upstream's Longhorn HelmRelease](https://github.com/upstream/home-ops/blob/main/kubernetes/kubernetes/apps/longhorn/app/helmrelease.yaml)
