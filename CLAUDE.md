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
- **CNI**: Cilium (replaces default Flannel) + Gateway API
- **Ingress**: ingress-nginx + MetalLB/kube-vip for LAN VIP
- **TLS**: cert-manager with Cloudflare DNS challenge (`*.jaw.dev` wildcard)
- **DNS**: external-dns auto-syncs Cloudflare records from ingresses
- **Storage**: Longhorn (block PVs) + nfs-subdir-external-provisioner (Synology NFS at 192.168.4.243)
- **Postgres**: CloudNativePG operator
- **Cache**: Valkey (Redis fork)
- **Secrets**: SOPS + age, decrypted in-cluster via Flux (same age key as before: `.sops/age-key.txt`)
- **Backups**: Restic per-app `HelmRelease` (replaces borgmatic)
- **Monitoring**: kube-prometheus-stack + kromgo for README badges
- **Updates**: Renovate + GitHub Actions

See `docs/kubernetes.md` for full stack table + bootstrap order, `docs/talos.md` for cluster setup.

## Repo Layout

```
kubernetes/
├── talos/                    # Talos config (talhelper)
├── flux/                     # core Flux config (TBD)
├── apps/                     # workloads (TBD)
│   └── <app>/
│       ├── app/helmrelease.yaml
│       ├── postgresql.yaml   # if needed
│       └── restic/helmrelease.yaml
└── templates/                # shared (cert-manager, reloader, reflector) (TBD)
```

Per-app pattern: app, its DB (if any), its restic backup — each in its own sub-folder with a `HelmRelease`.

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
