# Kubernetes

The k8s stack running on top of [Talos](talos.md). Modeled after [upstream/home-ops](https://github.com/upstream/home-ops) and [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template).

See [architecture.md](architecture.md) for how each component ties together, request flow diagrams, and the migration plan for moving jaw.dev to the cluster.

## Stack

| Layer              | Tool                                                                                                  | Purpose                                                                                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitOps             | [FluxCD](https://fluxcd.io/)                                                                          | Watches repo, reconciles cluster state                                                                                                                     |
| App chart          | [bjw-s/app-template](https://github.com/bjw-s/helm-charts)                                            | Universal Helm chart used by ~80% of apps — generates Deployment/Service/PVC/Ingress from a small values file                                              |
| CNI / Ingress / LB | [Cilium](https://cilium.io/)                                                                          | CNI + Gateway API + LB IPAM (replaces ingress-nginx — [retired March 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) — and MetalLB) |
| TLS                | [cert-manager](https://cert-manager.io/)                                                              | Cloudflare DNS challenge (same as now)                                                                                                                     |
| DNS                | [external-dns](https://github.com/kubernetes-sigs/external-dns)                                       | Auto-creates Cloudflare records                                                                                                                            |
| Auth/SSO           | [oauth2-proxy](https://oauth2-proxy.github.io/oauth2-proxy/)                                          | Google forward-auth via Gateway API ExtAuth (replaces traefik-forward-auth)                                                                                |
| Secrets            | SOPS (in-cluster via Flux)                                                                            | Reuse existing age key                                                                                                                                     |
| Storage            | [Longhorn](https://longhorn.io/)                                                                      | Replicated block PVs                                                                                                                                       |
| NFS                | [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) | Synology NFS PVs                                                                                                                                           |
| Postgres           | [CloudNativePG](https://cloudnative-pg.io/)                                                           | Postgres operator                                                                                                                                          |
| Cache              | [Valkey](https://valkey.io/)                                                                          | Redis fork                                                                                                                                                 |
| Backups            | [Volsync](https://volsync.readthedocs.io/) (Restic under the hood)                                    | PVC backup operator with restore-on-PVC-create; replaces borgmatic                                                                                         |
| Node labels        | [node-feature-discovery](https://github.com/kubernetes-sigs/node-feature-discovery)                   | Auto-labels nodes by hardware (CPU features, iGPU, etc.) so pods can target the right node                                                                 |
| GPU                | [intel-device-plugins](https://github.com/intel/intel-device-plugins-for-kubernetes)                  | Exposes Intel iGPU to pods (Plex hardware transcoding)                                                                                                     |
| Reloader           | [stakater/reloader](https://github.com/stakater/Reloader)                                             | Auto-restarts pods when ConfigMap/Secret changes                                                                                                           |
| Reflector          | [emberstack/reflector](https://github.com/emberstack/kubernetes-reflector)                            | Copies Secrets/ConfigMaps across namespaces (e.g. wildcard TLS cert, Cloudflare token)                                                                     |
| Cluster upgrades   | [system-upgrade-controller](https://github.com/rancher/system-upgrade-controller)                     | Drains + upgrades Talos nodes via CRDs (no laptop required)                                                                                                |
| Metrics            | [metrics-server](https://github.com/kubernetes-sigs/metrics-server)                                   | Powers `kubectl top` and HPA                                                                                                                               |
| Monitoring         | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts)                          | Prometheus + Grafana + Alertmanager                                                                                                                        |
| Badges             | [kromgo](https://github.com/kashalls/kromgo)                                                          | Cluster metrics as shields.io badges                                                                                                                       |
| Updates            | Renovate + GitHub Actions                                                                             | Same as docker-cd setup                                                                                                                                    |

## Bootstrap Order (current status)

| #   | Component                                                             | Status    |
| --- | --------------------------------------------------------------------- | --------- |
| 1   | Talos cluster up (see [talos.md](talos.md))                           | ✅ done   |
| 2   | Cilium with CNI + Gateway API + LB IPAM                               | ✅ done   |
| 3   | FluxCD                                                                | ✅ done   |
| 4   | SOPS decryption in Flux                                               | ✅ done   |
| 5   | metrics-server                                                        | ✅ done   |
| 6   | reloader                                                              | ✅ done   |
| 7   | reflector                                                             | ✅ done   |
| 8   | cert-manager + ClusterIssuers (Cloudflare DNS-01)                     | ✅ done   |
| 9   | cloudflared (Cloudflare Tunnel)                                       | ✅ done   |
| 10  | Cilium Gateway + LB IPPool                                            | ✅ done   |
| 11  | Longhorn (block storage on yanlon, default StorageClass)              | ✅ done   |
| 12  | Volsync (PVC backup operator)                                         | ✅ done   |
| 13  | nfs-subdir-external-provisioner (`/volume1/backup` → `nfs-backup` SC) | ✅ done   |
| 13b | nfs-subdir-external-provisioner for **media** (`/volume1/Media`)      | 🔮 later  |
| 14  | CNPG (Postgres operator) — see [cnpg.md](cnpg.md)                     | ✅ done   |
| 15  | **oauth2-proxy** (Google forward-auth)                                | ⏳ next   |
| 16  | **node-feature-discovery** + **intel-device-plugin** (for Plex)       | ⏳        |
| 17  | **kube-prometheus-stack**                                             | ⏳        |
| 18  | **system-upgrade-controller**                                         | ⏳        |
| 19  | **external-dns** (only when migrating jaw.dev)                        | 🔮 future |

## Repo Layout

```
kubernetes/
├── talos/                       # cluster bootstrap (Talos machine configs)
├── flux/                        # core Flux config
│   ├── flux-system/             # auto-generated by `flux bootstrap`; don't edit
│   └── repositories/helm/       # shared HelmRepositories (bjw-s, etc.)
└── apps/                        # workloads
    ├── <app>/                   # FLAT — for apps with their own namespace (default)
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── ks.yaml
    │   ├── postgresql.yaml      # CNPG Cluster (if needed)
    │   ├── app/                 # HelmRelease, HTTPRoute, ...
    │   └── restic/              # Volsync ReplicationSource (if needed)
    └── <namespace>/             # NESTED — only for multi-app namespaces (e.g. kube-system)
        └── <app>/{ks.yaml, app/}
```

See [adding-apps.md](adding-apps.md) for the canonical per-app pattern with a worked example.

## Migration Plan from docker-cd

Migrate in this order (low → high risk):

1. **Stateless single-binary apps first** — `dozzle`, `it-tools`, `cyberchef`, `ascii-movie`
2. **Stateless with config** — `uptime-kuma`, `homepage`, `seerr`
3. **Apps with SQLite** — `miniflux`, `vaultwarden`, `paperless-ngx`
4. **Apps with Postgres** — migrate DB to CNPG cluster first, then app
5. **Big stateful** — Plex, Immich, Home Assistant (last)

Keep docker-cd running on the OptiPlex 7050 (`apollo`) during migration. Once an app moves to k8s, remove from `apps/<name>/` in docker-cd.

## References

- [upstream/home-ops](https://github.com/upstream/home-ops) — primary reference
- [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) — base template most homelabs fork
- [bjw-s/home-ops](https://github.com/bjw-s/home-ops) — secondary reference
- [home-operations/template](https://github.com/home-operations/template) — community-maintained template
