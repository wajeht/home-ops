# FluxCD

GitOps controller for the cluster. Watches this repo and reconciles k8s state to match what's committed. After bootstrap, every change to `kubernetes/` lands in the cluster within minutes — no `kubectl apply` from your laptop.

## Prerequisites

- Talos cluster up with Cilium installed (see [getting-started.md](getting-started.md) steps 1-13)
- Flux CLI on your laptop: `brew install fluxcd/tap/flux`
- GitHub Personal Access Token with `repo` scope (only needed for bootstrap — Flux uses a deploy key after that)

## Install (one-time bootstrap)

Like Cilium, this is the **only** manual Flux install. After this, Flux self-manages via `kubernetes/flux/flux-system/`.

### 1. Load GitHub token

Reuse the existing token from `apps/gitea/.env.sops`:

```bash
export GITHUB_TOKEN=$(sopsd apps/gitea/.env.sops | grep -E '^(GITHUB_TOKEN|GH_TOKEN)=' | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")
echo "${GITHUB_TOKEN:0:4}..."   # sanity check, expect ghp_ or github_pat_
```

### 2. Run bootstrap

```bash
make flux-bootstrap
```

This runs:

```bash
flux bootstrap github \
  --owner=wajeht \
  --repository=home-ops \
  --branch=kubernetes \
  --path=kubernetes/flux \
  --personal
```

What it does:

1. Installs Flux controllers into the `flux-system` namespace (`source-controller`, `kustomize-controller`, `helm-controller`, `notification-controller`)
2. Creates a **deploy key** in your GitHub repo for ongoing reconciliation (Flux no longer needs your PAT after this)
3. Commits `kubernetes/flux/flux-system/{gotk-components.yaml, gotk-sync.yaml, kustomization.yaml}` to the `kubernetes` branch
4. Sets up a `GitRepository` + `Kustomization` watching `kubernetes/flux/` so Flux can self-update

### 3. Pull the new files locally

```bash
git pull
```

You'll see:

```
kubernetes/flux/flux-system/gotk-components.yaml  # the Flux controllers
kubernetes/flux/flux-system/gotk-sync.yaml        # the self-reconcile config
kubernetes/flux/flux-system/kustomization.yaml    # kustomize entrypoint
```

### 4. Verify

```bash
make flux-status
# or
flux get all -A
```

Expected output:

```
NAMESPACE    NAME                       REVISION                  SUSPENDED  READY
flux-system  gitrepository/flux-system  kubernetes@sha1:abc...    False      True
flux-system  kustomization/flux-system  kubernetes@sha1:abc...    False      True
```

## Repo layout (post-bootstrap)

Flux uses Kustomize as its primary engine. The directory structure mirrors upstream's pattern:

```
kubernetes/
├── flux/
│   └── flux-system/              # Flux self-management (auto-generated, don't edit)
│       ├── gotk-components.yaml
│       ├── gotk-sync.yaml
│       └── kustomization.yaml
├── apps/                          # workloads (you add these)
│   └── <namespace>/
│       └── <app>/
│           ├── ks.yaml            # Flux Kustomization pointing to app/
│           └── app/
│               ├── helmrelease.yaml
│               └── kustomization.yaml
└── talos/                         # Talos config (managed separately via talhelper)
```

### Per-app pattern

Every app gets a folder like this:

```
kubernetes/apps/kube-system/cilium/
├── ks.yaml                          # Flux Kustomization
└── app/
    ├── helmrelease.yaml             # the Helm install
    ├── kustomization.yaml           # kustomize entrypoint
    └── helmrepository.yaml          # the Helm chart source
```

## How to add a new app (the daily workflow)

1. Create `kubernetes/apps/<namespace>/<app>/app/helmrelease.yaml`
2. Create `kubernetes/apps/<namespace>/<app>/app/kustomization.yaml` listing the files in `app/`
3. Create `kubernetes/apps/<namespace>/<app>/ks.yaml` — a Flux Kustomization pointing to `./app`
4. Reference the new Kustomization from a parent (often `kubernetes/apps/<namespace>/kustomization.yaml`)
5. `git commit` + `git push`
6. Flux reconciles within ~1 minute, or force it with `make flux-reconcile`

See upstream's apps directory for the canonical pattern: [upstream/home-ops/kubernetes/kubernetes/apps](https://github.com/upstream/home-ops/tree/main/kubernetes/kubernetes/apps).

## Useful commands

```bash
make flux-status        # show all Flux resources state
make flux-reconcile     # force Flux to pull from git and reconcile NOW
make flux-tree          # show the dependency tree of Flux Kustomizations

flux logs --follow                     # live controller logs
flux get sources git                   # GitRepository sources
flux get helmreleases -A               # all HelmReleases
flux suspend kustomization <name>      # pause reconciliation (debug)
flux resume kustomization <name>       # resume
```

## Converting existing imperative installs to GitOps

Cilium was installed with `helm install` during bootstrap. To put it under Flux management:

1. Write `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml` with the same values we used in the imperative install (see [cilium.md](cilium.md))
2. Commit + push
3. Flux detects an existing release with the same name + namespace, adopts it (no reinstall)
4. From now on, Cilium upgrades = bump `chart.spec.version` in the HelmRelease, commit, push

Same pattern applies to anything we installed imperatively (e.g. the Gateway API CRDs).

## Why we use Flux (not ArgoCD)

|                  | Flux                            | ArgoCD                |
| ---------------- | ------------------------------- | --------------------- |
| UI               | None (CLI only)                 | Web UI                |
| Config language  | Kustomize-first, Helm via CRDs  | Helm/Kustomize/raw    |
| Multi-tenancy    | Lightweight                     | More mature           |
| Homelab adoption | Dominant (upstream, onedr0p, bjw-s) | Minority (joryirving) |

For a single-user homelab: Flux is lighter, has zero UI to maintain/secure, and matches the dominant homelab pattern (more tutorials to copy from). ArgoCD is more "job-skill relevant" but if you've used one, you can pick up the other.

## References

- [Flux docs: GitHub bootstrap](https://fluxcd.io/flux/installation/bootstrap/github/)
- [upstream's flux config](https://github.com/upstream/home-ops/tree/main/kubernetes/kubernetes/flux-system)
- [onedr0p/cluster-template flux setup](https://github.com/onedr0p/cluster-template/tree/main/templates/cluster/kubernetes/flux)
