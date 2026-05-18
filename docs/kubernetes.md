# Kubernetes

Planned k8s stack running on top of [Talos](talos.md). Modeled after [upstream/home-ops](https://github.com/upstream/home-ops) — the canonical homelab pattern.

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

## Bootstrap Order

1. Talos cluster up (see [talos.md](talos.md))
2. **Cilium** with CNI + Gateway API + LB IPAM all enabled (one chart, three jobs)
3. **FluxCD** (GitOps from this repo)
4. **metrics-server** (so `kubectl top` and HPA-aware charts work)
5. **reloader** (so subsequent config edits roll pods automatically)
6. **reflector** (so wildcard TLS cert + shared secrets can be reflected into other namespaces)
7. **cert-manager** + Cloudflare issuer (wildcard cert lives in `cert-manager` ns, reflector copies it everywhere)
8. **external-dns**
9. **oauth2-proxy** (Google forward-auth before exposing admin apps)
10. **Longhorn** + **nfs-subdir-external-provisioner**
11. **Volsync** (before any stateful app, so PVCs can be restored on first deploy)
12. **CNPG** (when first Postgres app needed)
13. **node-feature-discovery** + **intel-device-plugin** (before deploying Plex/transcoders)
14. **kube-prometheus-stack**
15. **system-upgrade-controller** (add once cluster is stable; automates Talos upgrades via CRD)

## Repo Layout (planned)

```
kubernetes/
├── talos/                       # cluster bootstrap (already exists)
├── flux/                        # core Flux config
├── apps/                        # workloads
│   └── <app>/
│       ├── app/helmrelease.yaml
│       ├── postgresql.yaml      # if needed
│       └── volsync.yaml         # ReplicationSource for PVC backup
└── templates/                   # shared (cert-manager, reloader, reflector)
```

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
