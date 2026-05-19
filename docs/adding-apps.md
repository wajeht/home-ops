# Adding Apps

How to add a new application to the cluster via GitOps. Every app — from `metrics-server` to `plex` — follows the same 5-file pattern.

## The Pattern

```
kubernetes/apps/<namespace>/<app>/
├── ks.yaml                          # Flux Kustomization (entrypoint from parent)
└── app/
    ├── kustomization.yaml           # kustomize entrypoint (lists files in app/)
    ├── helmrepository.yaml          # where to fetch the chart from
    └── helmrelease.yaml             # the install spec + values
```

Plus one line added to `kubernetes/apps/<namespace>/kustomization.yaml`.

## Worked Example: metrics-server

Below is the complete metrics-server setup we just deployed. Copy this and adjust for any future app.

### 1. The Flux Kustomization (`ks.yaml`)

This is what gets picked up by Flux's `apps` Kustomization when it scans `kubernetes/apps/`.

```yaml
# kubernetes/apps/kube-system/metrics-server/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: metrics-server
  namespace: flux-system
spec:
  targetNamespace: kube-system # where the app will be deployed
  interval: 30m # how often Flux re-checks
  path: ./kubernetes/apps/kube-system/metrics-server/app
  prune: true # delete resources when removed from git
  sourceRef:
    kind: GitRepository
    name: flux-system # the GitRepository created at bootstrap
  wait: true # wait for app to be ready
  timeout: 5m
```

Key fields:

- `targetNamespace` — where the app runs (NOT where the Flux resource lives, which is always `flux-system`)
- `path` — points to the `app/` subdirectory containing kustomize-buildable resources
- `prune: true` — Flux deletes resources when you remove them from git (essential for cleanup)
- `wait: true` — Flux blocks reconcile until the app is healthy (good for dependency ordering)

### 2. The kustomize entrypoint (`app/kustomization.yaml`)

Tells kustomize which files to include when building the app.

```yaml
# kubernetes/apps/kube-system/metrics-server/app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrepository.yaml
  - helmrelease.yaml
```

### 3. The Helm chart source (`app/helmrepository.yaml`)

Where Flux's source-controller fetches the chart from.

```yaml
# kubernetes/apps/kube-system/metrics-server/app/helmrepository.yaml
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  interval: 1h
  url: https://kubernetes-sigs.github.io/metrics-server/
```

> Tip: many apps use shared `HelmRepository` resources (e.g. `bjw-s` for app-template, `cilium` for cilium charts) so you don't repeat them per app. We'll factor those out into `kubernetes/templates/` later.

### 4. The HelmRelease (`app/helmrelease.yaml`)

The actual install — version, values, the works.

```yaml
# kubernetes/apps/kube-system/metrics-server/app/helmrelease.yaml
---
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: metrics-server
  namespace: kube-system
spec:
  interval: 1h
  chart:
    spec:
      chart: metrics-server # chart name in the repo
      version: 3.13.0 # pin a specific version (Renovate bumps this)
      sourceRef:
        kind: HelmRepository
        name: metrics-server
        namespace: kube-system
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      retries: 3
  values:
    args:
      # Talos kubelet uses a self-signed cert; metrics-server must skip TLS verification.
      - --kubelet-insecure-tls
      - --kubelet-preferred-address-types=InternalIP
      - --metric-resolution=30s
    metrics:
      enabled: false # enable once kube-prometheus-stack is installed
```

### 5. Add the app to its namespace's kustomization

```yaml
# kubernetes/apps/kube-system/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - metrics-server/ks.yaml
  # - <next-app>/ks.yaml
```

### 6. Add the namespace dir to apps/

Already done once when you first added the namespace; reuse for subsequent apps in the same namespace.

```yaml
# kubernetes/apps/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - kube-system
  # - cert-manager
  # - longhorn-system
```

## Daily workflow

```bash
# 1. Create the 4 app files
mkdir -p kubernetes/apps/<namespace>/<app>/app
$EDITOR kubernetes/apps/<namespace>/<app>/ks.yaml
$EDITOR kubernetes/apps/<namespace>/<app>/app/{kustomization,helmrepository,helmrelease}.yaml

# 2. Update the parent kustomization to list the new ks.yaml
$EDITOR kubernetes/apps/<namespace>/kustomization.yaml

# 3. Lint locally before pushing
make lint

# 4. Commit & push — Flux reconciles within ~1 min
git add kubernetes/apps/
git commit -m "feat(<namespace>): add <app>"
git push

# 5. Watch Flux pick it up (optional — auto-reconciles)
make flux-reconcile
flux get helmreleases -A
```

## Where to find values

For each app, write the `values:` block based on:

1. **Reference repos** — copy from upstream / onedr0p / bjw-s. Usually 90% of values match.
2. **The chart's own README** — read it before customizing
3. **Talos-specific gotchas** — anything that needs `--kubelet-insecure-tls`, hostPath workarounds, or capabilities

When in doubt, **search upstream's repo first**:

```bash
grep -rl "chart: <app-name>" ~/Dev/gabe-home-ops/kubernetes
```

## Common patterns to copy

### Stateless app with no DB

```
<app>/
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── helmrepository.yaml
    └── helmrelease.yaml
```

(Same as metrics-server)

### App with Postgres

```
<app>/
├── ks.yaml                       # depends on cnpg
├── app/
│   └── ...                       # app's HelmRelease
└── postgresql.yaml               # CNPG Cluster resource
```

### App with Volsync backup

```
<app>/
├── ks.yaml
├── app/
│   └── ...
└── volsync.yaml                  # ReplicationSource for PVC backup
```

## Dependency ordering

Some apps depend on others (e.g. cert-manager must exist before an app requests TLS). Flux handles this via `dependsOn` in the `Kustomization`:

```yaml
spec:
  dependsOn:
    - name: cert-manager # block this until cert-manager Kustomization is Ready
      namespace: flux-system
```

## References

- [upstream's apps directory](https://github.com/upstream/home-ops/tree/main/kubernetes/kubernetes/apps) — primary reference
- [onedr0p/cluster-template apps](https://github.com/onedr0p/cluster-template/tree/main/templates/cluster/kubernetes/apps) — pattern source
- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux HelmRelease API](https://fluxcd.io/flux/components/helm/helmreleases/)
