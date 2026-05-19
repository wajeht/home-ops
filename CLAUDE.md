# CLAUDE.md

Guidance for Claude Code working in this repository.

## Branch Context

This repo is mid-migration from Docker Compose (docker-cd) → Kubernetes.

- **`main`** — running production on docker-cd (Docker Compose stacks in `apps/`)
- **`kubernetes`** (this branch) — building the k8s replacement; docker-cd dirs/scripts already stripped

Until migration is complete, `apps/` stays on `main` only. Workloads on this branch live under `kubernetes/apps/`.

## Commit Rules

- Never add `Co-Authored-By:` to commit messages
- Use conventional commit messages, short and concise

## Target Architecture

GitOps-driven k8s homelab on Talos Linux, modeled after [upstream/home-ops](https://github.com/upstream/home-ops).

- **Cluster**: 2 nodes — `soapwa` (CP, 192.168.4.162) + `yanlon` (worker, 192.168.4.163). `apollo` (.161) joins after docker-cd is retired.
- **GitOps**: FluxCD watches this repo, reconciles `kubernetes/apps/`
- **App chart**: bjw-s/app-template — universal Helm chart used by ~80% of apps
- **CNI / Ingress / LB**: Cilium handles all three — CNI (replaces default Flannel), Gateway API (replaces ingress-nginx after its [March 2026 retirement](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)), and LB IPAM for LAN VIPs (no MetalLB needed)
- **External entry**: Cloudflare Tunnel (`cloudflared` in cluster) — outbound only, no port forward, no exposed home IP. **Locally-managed** tunnel (created via `cloudflared tunnel create`, not the dashboard) so `config.yml` in git is authoritative. The 7050 (docker-cd) still owns port 443 for `*.jaw.dev`, so the cluster uses `*.wajeht.com` via tunnel.
- **TLS**: Cloudflare edge terminates HTTPS for tunneled traffic. cert-manager is installed and ready (with `letsencrypt-production` + `letsencrypt-staging` ClusterIssuers using Cloudflare DNS-01) for when we need in-cluster TLS (Gateway listeners, mTLS, or post-jaw.dev migration).
- **DNS**: one wildcard CNAME `*.wajeht.com → <tunnel-id>.cfargotunnel.com` covers every app; `config.yml` has a single catch-all rule and HTTPRoutes do the per-app routing. Adding a new app needs zero DNS or `config.yml` edits. external-dns NOT installed (and not needed for this pattern).
- **Auth/SSO**: oauth2-proxy with Google as IdP (replaces traefik-forward-auth from docker-cd era)
- **Storage**: Longhorn (block PVs, default StorageClass) — yanlon's 1TB SATA mounted at `/var/mnt/longhorn` via Talos UserVolume; `numberOfReplicas: 1` until soapwa gets a data disk.
- **NFS storage**: nfs-subdir-external-provisioner → Synology `/volume1/backup` exposed as the `nfs-backup` StorageClass with `pathPattern: k8s/${.PVC.namespace}-${.PVC.name}-${.PVC.uid}` (keeps k8s data separate from docker-cd's borgmatic dirs). Used by Volsync as the Restic repo target. A second provisioner for `/volume1/Media` will be added when Plex migrates.
- **Postgres**: CloudNativePG operator
- **Cache**: Valkey (Redis fork)
- **Secrets**: SOPS + age, decrypted in-cluster via Flux (same age key as before: `.sops/age-key.txt`)
- **Backups**: Volsync operator + `nfs-backup` StorageClass wired up. Per-app pattern: small PVC on `nfs-backup` (auto-creates `/volume1/backup/k8s/<ns>-<pvc>/` on Synology) + Restic Secret + `ReplicationSource` writing to `/repo`. Auto-restore on PVC create via annotations.
- **Node labels**: node-feature-discovery auto-labels nodes by hardware (pairs with intel-device-plugin)
- **GPU**: intel-device-plugin exposes iGPU for Plex transcoding
- **Reloader**: stakater/reloader auto-restarts pods on ConfigMap/Secret changes
- **Reflector**: emberstack/reflector copies Secrets/ConfigMaps across namespaces (wildcard cert, shared tokens)
- **Cluster upgrades**: system-upgrade-controller drains + upgrades Talos nodes via CRDs
- **Metrics**: metrics-server powers `kubectl top` and HPA
- **Monitoring**: kube-prometheus-stack + kromgo for README badges
- **Updates**: Renovate + GitHub Actions

Docs index:

- `docs/architecture.md` — **start here** — how everything ties together (request flow, GitOps loop, secrets flow, jaw.dev migration plan)
- `docs/getting-started.md` — zero-to-working-cluster bootstrap playbook
- `docs/adding-apps.md` — canonical per-app GitOps pattern
- `docs/kubernetes.md` — stack table + bootstrap status checklist
- `docs/talos.md` — Talos cluster setup, talhelper cheatsheet, day-2 ops
- `docs/cilium.md` — Cilium install deep dive
- `docs/flux.md` — FluxCD bootstrap + workflow
- `docs/cloudflared.md` — Cloudflare Tunnel as cluster's entry point
- `docs/longhorn.md` — block storage (Talos UserVolume + Longhorn HelmRelease)
- `docs/volsync.md` — PVC backup operator + per-app `ReplicationSource` pattern
- `docs/nfs-storage.md` — Synology NFS-backed PVCs via nfs-subdir-external-provisioner
- `docs/cnpg.md` — CloudNativePG operator + per-app `Cluster` pattern

## Repo Layout

```
kubernetes/
├── talos/                       # Talos config (talhelper-managed)
├── flux/                        # FluxCD self-management
│   ├── flux-system/             # auto-generated by flux bootstrap; don't edit
│   └── repositories/helm/       # shared HelmRepositories (bjw-s, etc.)
└── apps/                        # workloads (added via git commits)
    │
    ├── <app>/                   # FLAT — for apps with their own namespace (1:1)
    │   ├── kustomization.yaml
    │   ├── namespace.yaml       # the app's namespace
    │   ├── ks.yaml              # Flux Kustomization(s)
    │   ├── postgresql.yaml      # CNPG Cluster (if app needs Postgres)
    │   ├── app/                 # app manifests (HelmRelease, HTTPRoute, ...)
    │   └── restic/              # Volsync ReplicationSource (if app needs backups)
    │
    └── <namespace>/             # NESTED — only for namespaces with multiple apps
        ├── kustomization.yaml   # lists each app
        ├── <app1>/{ks.yaml, app/}
        └── <app2>/{ks.yaml, app/}
```

Layout rule: **flat at the top level when an app has its own namespace** (e.g. `apps/longhorn/` ⇒ `longhorn-system` ns, `apps/cnpg/` ⇒ `cnpg-system` ns, `apps/echo/` ⇒ `echo` ns). **Namespace-grouped only when a namespace hosts multiple apps** (today: `apps/kube-system/` for cilium-gateway/metrics-server/reflector/reloader). The `default` namespace is intentionally unused — every app gets its own.

Per-app pattern: the app, its DB (if any), and its Volsync `ReplicationSource` — each in its own sub-folder (`app/`, `postgresql.yaml`, `restic/`).

## Key Conventions

- **No custom container builds** — only pre-built images from registries. Pin every image with `tag@sha256:...` digest.
- **Helm-first** — prefer existing Helm charts (bjw-s app-template, official charts) over hand-rolled manifests
- **Namespace per app** — keeps RBAC and resource limits clean
- **Secrets** — `.sops.yaml` already configured for `.env.sops` and `talsecret*.yaml`. Add patterns as needed for new file types. Always use `--input-type dotenv --output-type dotenv` for `.env.sops` files.

## Operational Rules

- **NEVER commit or push to git** — user handles all git ops
- **NEVER run destructive commands** on cluster nodes without explicit permission
- **NEVER edit/modify anything on the server via SSH** unless explicitly told — always edit locally, commit, push, let Flux reconcile
- SSH is read-only checks (logs, status, verify) by default
- ALWAYS run lint/format/typecheck before committing in any project

## Tooling

```bash
# Talos cluster management
cd kubernetes/talos
talhelper genconfig                    # regen machine configs
talhelper gencommand apply | bash      # apply to all nodes
talhelper gencommand bootstrap | bash  # bootstrap etcd (once)
talosctl --talosconfig clusterconfig/talosconfig <cmd>

# Kubernetes
kubectl get nodes -o wide
kubectl get pods -A
flux get all -A                        # after Flux is bootstrapped

# SOPS
export SOPS_AGE_KEY_FILE=./.sops/age-key.txt
sops -e --input-type dotenv --output-type dotenv .env > .env.sops
sops .env.sops                          # edit encrypted
```

## Hardware / Network

- **soapwa** (.162) — OptiPlex 5050, i7-6700, 32GB, Talos CP
- **yanlon** (.163) — OptiPlex 7070, i7-9700T, 32GB, Talos worker
- **apollo** (.161) — OptiPlex 7050, i7-7700, 32GB, currently docker-cd (target: future worker)
- **NAS** — Synology DS923+ at 192.168.4.243 (NFS for media + PVs)
- **Router** — UniFi Cloud Gateway Fiber (Cloudflare-IP-only on 443, region-locked to US)
- **SOPS age key**: `.sops/age-key.txt` (repo-local) and `~/.sops/age-key.txt` (on hosts)
- **age recipient**: `age1jcnrthtt049n6e2w2hpyq8r342q97r3ws44m0maty4dx527yvd7qyucfnp`

## Communication Style

- Use simple real-world analogies for technical concepts (3-5 sentences max)
- Concrete examples over abstract theory
- Default to terse responses — 1–3 sentences, one proposal not menus
- Warn about risky/destructive actions BEFORE the user takes them
- Never redirect `sops` output to the same file it's reading; use a temp file
