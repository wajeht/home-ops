# Adding Apps

How to add a new application to the cluster via GitOps. Every app — from `metrics-server` to `plex` — follows one of two layouts depending on whether its namespace will be shared.

## The Pattern (Rule of Thumb)

**Flat layout** when an app has its own namespace (1 app == 1 namespace). This is the default for ~95% of apps.

```
kubernetes/apps/<app>/
├── kustomization.yaml           # lists [namespace, ks, postgresql, ...]
├── namespace.yaml               # the app's namespace
├── ks.yaml                      # Flux Kustomization(s)
├── postgresql.yaml              # CNPG Cluster (if app uses Postgres)
├── app/                         # app manifests
│   ├── kustomization.yaml
│   ├── helmrelease.yaml
│   └── httproute.yaml
└── restic/                      # Volsync ReplicationSource (if app needs backups)
    ├── kustomization.yaml
    ├── pvc.yaml
    ├── replicationsource.yaml
    └── secret.sops.yaml
```

Examples: `apps/longhorn/` (ns=`longhorn-system`), `apps/cnpg/` (ns=`cnpg-system`), `apps/hello-world/`.

**Namespace-grouped layout** when multiple apps share a namespace.

```
kubernetes/apps/<namespace>/
├── kustomization.yaml           # lists each app's ks.yaml
├── <app1>/
│   ├── ks.yaml
│   └── app/...
└── <app2>/
    ├── ks.yaml
    └── app/...
```

Example today: `apps/kube-system/` (hosts cilium-gateway, metrics-server, reflector, reloader). The `default` namespace is intentionally unused — every app gets its own.

Rule of thumb: if you'd ever add a second app to this namespace, use the namespace-grouped layout. Otherwise stay flat.

## Worked Example: hello-world (flat, Postgres-backed)

The full hello-world app — bjw-s app-template, CNPG `Cluster`, HTTPRoute through the Cilium Gateway. Copy this for any Postgres-backed app.

### 1. Root kustomization (`kustomization.yaml`)

What the parent `apps/` build picks up.

```yaml
# kubernetes/apps/hello-world/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - postgresql.yaml
  - ks.yaml
```

### 2. Namespace (`namespace.yaml`)

```yaml
# kubernetes/apps/hello-world/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: hello-world
```

### 3. The Flux Kustomization (`ks.yaml`)

```yaml
# kubernetes/apps/hello-world/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: hello-world
  namespace: flux-system
spec:
  targetNamespace: hello-world
  interval: 30m
  path: ./kubernetes/apps/hello-world/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  dependsOn:
    - name: cnpg # block until CNPG operator is ready
    - name: cilium-gateway # block until Gateway exists
  wait: true
  timeout: 5m
```

Key fields:

- `targetNamespace` — where the app's resources land (NOT where the Flux resource lives, which is always `flux-system`)
- `path` — points to the `app/` subdirectory; everything under it gets kustomize-built and applied
- `prune: true` — Flux deletes resources you remove from git
- `wait: true` — blocks reconcile until the app reports Ready (good for downstream `dependsOn`)
- `dependsOn` — Flux orders this Kustomization after the listed ones; use to express things like "wait for CNPG operator before creating a Postgres-backed app"

### 4. The Postgres `Cluster` (`postgresql.yaml`)

Sits at the app root (not under `app/`) so it's applied **before** the app's HelmRelease — that way the auto-created `postgresql-app` Secret with credentials exists when the app pod tries to consume it.

```yaml
# kubernetes/apps/hello-world/postgresql.yaml
---
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgresql
  namespace: hello-world
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:17.5-minimal-bookworm@sha256:...
  enableSuperuserAccess: false
  storage:
    storageClass: longhorn-db
    size: 2Gi
  bootstrap:
    initdb:
      database: hello
      owner: hello # CNPG auto-creates Secret `postgresql-app` with username/password/uri
```

### 5. App `kustomization.yaml` (`app/kustomization.yaml`)

```yaml
# kubernetes/apps/hello-world/app/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - helmrelease.yaml
  - httproute.yaml
```

### 6. The HelmRelease (`app/helmrelease.yaml`)

Uses bjw-s app-template (universal chart for ~80% of apps in this repo).

```yaml
# kubernetes/apps/hello-world/app/helmrelease.yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/app-template-5.0.0/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: hello-world
  namespace: hello-world
spec:
  chart:
    spec:
      chart: app-template
      version: 5.0.0
      reconcileStrategy: ChartVersion
      sourceRef:
        kind: HelmRepository
        namespace: flux-system
        name: bjw-s # shared HelmRepository at kubernetes/flux/repositories/helm/bjw-s.yaml
  interval: 1h
  driftDetection: { mode: enabled }
  values:
    controllers:
      hello-world:
        containers:
          app:
            image:
              repository: ghcr.io/wajeht/hello-world
              tag: 01a97c3@sha256:... # pin every image with @sha256:
              pullPolicy: IfNotPresent
            env:
              PORT: "3000"
              DATABASE_URL:
                secretKeyRef:
                  name: postgresql-app # auto-created by CNPG
                  key: uri
            probes:
              liveness: &probe
                enabled: true
                type: HTTP
                path: /healthz
                port: 3000
              readiness: *probe
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: true
              capabilities: { drop: [ALL] }
        pod:
          securityContext:
            runAsNonRoot: true
            runAsUser: 65532
            fsGroup: 65532
            fsGroupChangePolicy: OnRootMismatch
            seccompProfile: { type: RuntimeDefault }
    service:
      app:
        controller: hello-world
        ports:
          http:
            port: 3000
```

### 7. The HTTPRoute (`app/httproute.yaml`)

Attaches the Service to the Cilium `internet` Gateway.

```yaml
# kubernetes/apps/hello-world/app/httproute.yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hello-world
  namespace: hello-world
spec:
  parentRefs:
    - name: internet
      namespace: kube-system
      sectionName: http
  hostnames:
    - hello-world.wajeht.com
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: hello-world
          port: 3000
```

### 8. Register the new dir in `apps/kustomization.yaml`

```yaml
# kubernetes/apps/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - cert-manager
  - cnpg
  - hello-world # ← new
  - kube-system
  - longhorn
  - ...
```

### 9. (no DNS/tunnel step needed)

Nothing to wire up per app. The wildcard CNAME `*.wajeht.com → tunnel` covers any subdomain you create, and the cloudflared `config.yml` is a single catch-all that forwards everything to the Cilium Gateway. The HTTPRoute above (Step 7) does the per-app matching by Host header. See [cloudflared.md](cloudflared.md) if curious about the wildcard setup.

## Daily workflow

```bash
# 1. Scaffold the app dir (flat layout — for 1:1 namespace apps)
mkdir -p kubernetes/apps/<app>/app
$EDITOR kubernetes/apps/<app>/{kustomization,namespace,ks}.yaml
$EDITOR kubernetes/apps/<app>/app/{kustomization,helmrelease}.yaml

# 2. Add the app dir to apps/kustomization.yaml
$EDITOR kubernetes/apps/kustomization.yaml

# 3. Lint locally before pushing
make kustomize-lint

# 4. Commit & push — Flux reconciles within ~1 min
git add kubernetes/apps/<app> kubernetes/apps/kustomization.yaml
git commit -m "feat(<app>): add <app>"
git push

# 5. Watch Flux pick it up
flux get kustomizations -A
flux get helmreleases -A
```

## Where to find values

For each app's HelmRelease `values:`, write the block based on:

1. **Reference repos** — copy from upstream / onedr0p / bjw-s. Usually 90% of values match.
2. **The chart's own README** — read it before customizing.
3. **Talos-specific gotchas** — anything that needs `--kubelet-insecure-tls`, hostPath workarounds, or capabilities.

When in doubt, search upstream's repo first:

```bash
gh search code "chart: <app-name>" --repo upstream/home-ops --extension yaml
```

## Common shapes

### Stateless app, no DB, no backup

```
<app>/
├── kustomization.yaml          # [namespace, ks]
├── namespace.yaml
├── ks.yaml
└── app/
    ├── kustomization.yaml
    ├── helmrelease.yaml
    └── httproute.yaml          # if it serves HTTP
```

### App with Postgres (via CNPG)

```
<app>/
├── kustomization.yaml          # [namespace, postgresql, ks]
├── namespace.yaml
├── postgresql.yaml             # CNPG Cluster — applied BEFORE the app/
├── ks.yaml                     # dependsOn: cnpg
└── app/
    └── ...                     # consumes postgresql-app Secret (uri key)
```

### App with Volsync backup

Add `dependsOn: volsync` to `ks.yaml`, plus a `restic/` sibling:

```
<app>/
├── kustomization.yaml          # [namespace, ks]
├── namespace.yaml
├── ks.yaml                     # 2 Flux Kustomizations: app + restic
├── app/...
└── restic/
    ├── kustomization.yaml
    ├── pvc.yaml                # tiny PVC on `nfs-backup` SC for restic repo
    ├── replicationsource.yaml  # snapshots app PVC → restic push
    └── secret.sops.yaml        # RESTIC_PASSWORD (SOPS-encrypted)
```

## Dependency ordering

Some apps depend on others (e.g. cert-manager must exist before an app requests TLS). Express via `dependsOn` in the Flux `Kustomization`:

```yaml
spec:
  dependsOn:
    - name: cert-manager # waits until this Kustomization is Ready
      namespace: flux-system
```

Common dependencies:

- `cnpg` — for any Postgres-backed app
- `cilium-gateway` — for any app with an HTTPRoute
- `cert-manager` + `cert-manager-issuers` — for any app needing in-cluster TLS
- `volsync` — for any app with a `ReplicationSource`

## References

- [upstream's apps directory](https://github.com/upstream/home-ops/tree/main/kubernetes/kubernetes/apps) — primary reference (uses the flat layout for all apps)
- [onedr0p/cluster-template apps](https://github.com/onedr0p/cluster-template/tree/main/templates/cluster/kubernetes/apps) — pattern source (uses namespace-grouped throughout)
- [Flux Kustomization API](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Flux HelmRelease API](https://fluxcd.io/flux/components/helm/helmreleases/)
- [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) — universal chart we use for ~80% of apps
