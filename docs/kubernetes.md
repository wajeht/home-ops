# Kubernetes

Planned k8s stack running on top of [Talos](talos.md). Modeled after [upstream/home-ops](https://github.com/upstream/home-ops) — the canonical homelab pattern.

## Stack

| Layer         | Tool                                                                                                  | Purpose                                |
| ------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------- |
| GitOps        | [FluxCD](https://fluxcd.io/)                                                                          | Watches repo, reconciles cluster state |
| CNI           | [Cilium](https://cilium.io/)                                                                          | Networking + Gateway API               |
| Ingress       | [ingress-nginx](https://github.com/kubernetes/ingress-nginx)                                          | HTTP/S ingress (replaces Traefik)      |
| Load balancer | [MetalLB](https://metallb.universe.tf/) + [kube-vip](https://kube-vip.io/)                            | LAN VIP for API + ingress              |
| TLS           | [cert-manager](https://cert-manager.io/)                                                              | Cloudflare DNS challenge (same as now) |
| DNS           | [external-dns](https://github.com/kubernetes-sigs/external-dns)                                       | Auto-creates Cloudflare records        |
| Secrets       | SOPS (in-cluster via Flux)                                                                            | Reuse existing age key                 |
| Storage       | [Longhorn](https://longhorn.io/)                                                                      | Replicated block PVs                   |
| NFS           | [nfs-subdir-external-provisioner](https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner) | Synology NFS PVs                       |
| Postgres      | [CloudNativePG](https://cloudnative-pg.io/)                                                           | Postgres operator                      |
| Cache         | [Valkey](https://valkey.io/)                                                                          | Redis fork                             |
| Backups       | [Restic](https://restic.net/) per-app                                                                 | Replaces borgmatic                     |
| Monitoring    | [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts)                          | Prometheus + Grafana + Alertmanager    |
| Badges        | [kromgo](https://github.com/kashalls/kromgo)                                                          | Cluster metrics as shields.io badges   |
| Updates       | Renovate + GitHub Actions                                                                             | Same as docker-cd setup                |

## Bootstrap Order

1. Talos cluster up (see [talos.md](talos.md))
2. **Cilium** (replaces default Flannel)
3. **kube-vip** (HA VIP for API endpoint)
4. **MetalLB** (LAN load balancer IPs)
5. **FluxCD** (GitOps from this repo)
6. **cert-manager** + Cloudflare issuer
7. **external-dns**
8. **ingress-nginx**
9. **Longhorn** + **nfs-subdir-external-provisioner**
10. **CNPG** (when first Postgres app needed)
11. **kube-prometheus-stack**

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
