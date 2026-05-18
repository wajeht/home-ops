# Kubernetes

Planned k8s stack running on top of [Talos](talos.md). Modeled after [upstream/home-ops](https://github.com/upstream/home-ops) — the canonical homelab pattern.

## Stack

| Layer              | Tool                                                                                                  | Purpose                                                                                                                                                    |
| ------------------ | ----------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| GitOps             | [FluxCD](https://fluxcd.io/)                                                                          | Watches repo, reconciles cluster state                                                                                                                     |
| CNI / Ingress / LB | [Cilium](https://cilium.io/)                                                                          | CNI + Gateway API + LB IPAM (replaces ingress-nginx — [retired March 2026](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) — and MetalLB) |
| TLS                | [cert-manager](https://cert-manager.io/)                                                              | Cloudflare DNS challenge (same as now)                                                                                                                     |
| DNS                | [external-dns](https://github.com/kubernetes-sigs/external-dns)                                       | Auto-creates Cloudflare records                                                                                                                            |
| Secrets            | SOPS (in-cluster via Flux)                                                                            | Reuse existing age key                                                                                                                                     |
| Storage            | [Longhorn](https://longhorn.io/)                                                                      | Replicated block PVs                                                                                                                                       |
| NFS                | [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) | Synology NFS PVs                                                                                                                                           |
| Postgres           | [CloudNativePG](https://cloudnative-pg.io/)                                                           | Postgres operator                                                                                                                                          |
| Cache              | [Valkey](https://valkey.io/)                                                                          | Redis fork                                                                                                                                                 |
| Backups            | [Restic](https://restic.net/) per-app                                                                 | Replaces borgmatic                                                                                                                                         |
| Monitoring         | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts)                          | Prometheus + Grafana + Alertmanager                                                                                                                        |
| Badges             | [kromgo](https://github.com/kashalls/kromgo)                                                          | Cluster metrics as shields.io badges                                                                                                                       |
| Updates            | Renovate + GitHub Actions                                                                             | Same as docker-cd setup                                                                                                                                    |

## Bootstrap Order

1. Talos cluster up (see [talos.md](talos.md))
2. **Cilium** with CNI + Gateway API + LB IPAM all enabled (one chart, three jobs)
3. **FluxCD** (GitOps from this repo)
4. **cert-manager** + Cloudflare issuer
5. **external-dns**
6. **Longhorn** + **nfs-subdir-external-provisioner**
7. **CNPG** (when first Postgres app needed)
8. **kube-prometheus-stack**

## Repo Layout (planned)

```
kubernetes/
├── talos/                       # cluster bootstrap (already exists)
├── flux/                        # core Flux config
├── apps/                        # workloads
│   └── <app>/
│       ├── app/helmrelease.yaml
│       ├── postgresql.yaml      # if needed
│       └── restic/helmrelease.yaml
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
