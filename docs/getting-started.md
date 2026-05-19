# Getting Started

Step-by-step bootstrap of a fresh Talos + k8s cluster, from zero hardware to a working multi-node cluster with Cilium. Run these in order — each step has prerequisites from the previous one.

For component-specific deep dives see [talos.md](talos.md), [cilium.md](cilium.md), and [kubernetes.md](kubernetes.md).

## Prerequisites

Tools (install once on your laptop):

```bash
brew install siderolabs/tap/talosctl talhelper sops age helm kubectl
```

A USB stick (≥4 GB) and physical access to your nodes (you'll need to boot them from USB at least once).

## Step 1 — Generate Talos cluster secrets (one-time, if not already done)

Only run if `kubernetes/talos/talsecret.sops.yaml` doesn't exist yet. These secrets define the cluster's identity (certs, bootstrap tokens). They survive node wipes.

```bash
cd kubernetes/talos
talhelper gensecret > talsecret.sops.yaml
sops -e -i talsecret.sops.yaml
cd ../..
```

## Step 2 — Define cluster topology

Edit `kubernetes/talos/talconfig.yaml`:

- `clusterName`, `talosVersion`, `kubernetesVersion`
- `endpoint` — usually `https://<CP_IP>:6443`
- `nodes:` — IP, hostname, role, install disk for each node
- `cniConfig: { name: none }` — required so Cilium owns networking
- Patch `cluster.proxy.disabled: true` — required so Cilium replaces kube-proxy

See current [talconfig.yaml](../kubernetes/talos/talconfig.yaml) for the canonical example.

## Step 3 — Flash Talos USB

```bash
# Download the custom Talos ISO (has system extensions baked in)
curl -LO https://factory.talos.dev/image/cd0648ed93c7bcf5c362fa0dc72ca43e9e0c0eccf8d46413b6aa35ee71c6c55c/v1.12.6/metal-amd64.iso
```

Flash to USB with [Balena Etcher](https://etcher.balena.io/).

**Why a custom image, not vanilla Talos?** The image embeds system extensions (`i915` for Intel GPU, `iscsi-tools` for Longhorn, `nut-client` for UPS, etc.). The schematic ID is in [talos.md](talos.md).

## Step 4 — Boot each node from USB

For each node:

1. Plug USB into the machine
2. Power on, hit `F12` at the Dell splash, pick the USB drive
3. Talos boots into **maintenance mode** (loaded into RAM from USB; no install yet)
4. The node shows up on the LAN at the IP you set in `talconfig.yaml`

Verify it's responding:

```bash
ping -c 2 <NODE_IP>
talosctl get disks --insecure --nodes <NODE_IP> --endpoints <NODE_IP> | grep -v loop
```

You should see the install disk (`/dev/sdb`, `/dev/nvme0n1`, etc.) plus the USB (`/dev/sda`).

> **You only need to boot from USB once** — after `apply-config` installs Talos to disk in the next step, the node boots from disk on subsequent reboots.

## Step 5 — Generate machine configs

```bash
make talos-config
```

This regenerates `kubernetes/talos/clusterconfig/*.yaml` from `talconfig.yaml`. Gitignored — never commit these.

## Step 6 — Apply configs (first-time, with `--insecure`)

Nodes in maintenance mode have no auth/TLS yet, so we apply with `--insecure`:

```bash
make talos-apply-insecure
```

Each node receives its config, installs Talos onto its install disk, and reboots into the installed Talos (no longer needs USB). Takes ~2 min.

If you only want to apply to one node:

```bash
cd kubernetes/talos
talhelper gencommand apply --node <hostname> --extra-flags=--insecure | bash
cd ../..
```

> **Future config changes use `make talos-apply`** (no `--insecure`) — nodes have cluster certs now.

## Step 7 — Pull USB sticks

Once `apply-config` finishes, Talos is on the disk. The USB can be removed (don't reboot yet, since Talos is still finalizing).

## Step 8 — Bootstrap etcd on the control plane

Do this **once**, only on the first control plane node:

```bash
make talos-bootstrap
```

This initializes the etcd cluster. After this, the k8s control plane comes up (apiserver, scheduler, controller-manager).

## Step 9 — Pull kubeconfig

```bash
make talos-kubeconfig
```

Now `kubectl` works against your new cluster.

## Step 10 — Verify nodes are present (still NotReady)

```bash
make nodes
```

Expected:

```
NAME     STATUS     ROLES           AGE   VERSION
soapwa   NotReady   control-plane   1m    v1.35.2
yanlon   NotReady   <none>          1m    v1.35.2
```

`NotReady` is correct — there's no CNI yet. Next step fixes that.

## Step 11 — Clean up auto-created kube-proxy DaemonSet

Even with `cluster.proxy.disabled: true`, Talos's first-boot bootkube creates a `kube-proxy` DaemonSet. The `disabled: true` only prevents _future_ re-installs; you must delete the existing one:

```bash
kubectl -n kube-system delete daemonset kube-proxy
kubectl -n kube-system delete configmap kube-proxy 2>/dev/null || true
```

## Step 12 — Install Cilium

The one-time chicken-and-egg bootstrap (Flux can't run without networking, so we install Cilium imperatively first). See [cilium.md](cilium.md) for full details + per-flag explanations.

```bash
# Gateway API CRDs (Cilium gatewayAPI.enabled=true requires them)
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml

helm repo add cilium https://helm.cilium.io/
helm repo update cilium

helm install cilium cilium/cilium \
  --version 1.19.3 \
  --namespace kube-system \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set gatewayAPI.enabled=true \
  --set l2announcements.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true
```

## Step 13 — Verify cluster is healthy

```bash
# All nodes Ready
make nodes

# All kube-system pods Running (no Pending, no CrashLoopBackOff)
make pods

# Cilium specifically
kubectl -n kube-system get pods -l k8s-app=cilium
```

You should see:

- ✅ All nodes `Ready`
- ✅ CoreDNS pods `Running`
- ✅ Cilium agent (`cilium-XXXXX`), operator, envoy all `Running` on every node
- ✅ Hubble relay + UI `Running`

## Step 14 — Install FluxCD (GitOps)

The second one-time imperative install. After this, every other component is added via git commits. See [flux.md](flux.md) for full details.

```bash
brew install fluxcd/tap/flux

# Load existing token from apps/gitea/.env.sops (reuse — no new PAT needed)
export GITHUB_TOKEN=$(sopsd apps/gitea/.env.sops | grep -E '^(GITHUB_TOKEN|GH_TOKEN)=' | head -1 | cut -d= -f2- | tr -d '"' | tr -d "'")

make flux-bootstrap
git pull              # pull the new kubernetes/flux/flux-system/ files committed by Flux
make flux-status      # verify both GitRepository and Kustomization are READY
```

Flux now watches the `kubernetes/` branch path `kubernetes/flux/` and reconciles every minute.

## Step 15 — Set up the apps scaffold

Create the directory Flux will watch for app HelmReleases. Three files:

```bash
# kubernetes/flux/kustomization.yaml      — parent listing flux-system + apps.yaml
# kubernetes/flux/apps.yaml               — Flux Kustomization watching kubernetes/apps/
# kubernetes/apps/kustomization.yaml      — empty stub for now
```

See [adding-apps.md](adding-apps.md) for the canonical per-app pattern. After committing, verify Flux picks it up:

```bash
flux get kustomizations -A     # should now show: flux-system + apps
```

## Step 16 — First app: metrics-server

The canonical "first GitOps-managed app" — small, dependency-free, validates the scaffold.

See [adding-apps.md](adding-apps.md) for the full pattern. Once committed:

```bash
flux reconcile source git flux-system
flux get helmreleases -A       # metrics-server: Ready
kubectl top nodes              # confirms metrics-server is working
```

**Talos quirk:** metrics-server needs `--kubelet-insecure-tls` in its args (Talos kubelet cert is self-signed). Already baked into our `helmrelease.yaml`.

## Step 17 — Enable SOPS decryption in Flux (one-time)

Required before deploying anything that needs a Secret (cert-manager, cloudflared, future apps).

```bash
# Create the sops-age Secret manually — Flux can't decrypt the secret that decrypts secrets
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=.sops/age-key.txt

# Update kubernetes/flux/apps.yaml to add:
#   spec.decryption: { provider: sops, secretRef: { name: sops-age } }

# Also add a SOPS rule for k8s Secrets in .sops.yaml:
#   - path_regex: kubernetes/.*\.sops\.yaml$
#     encrypted_regex: ^(data|stringData)$
#     age: <your-age-recipient>
```

After this, every `*.sops.yaml` you commit gets decrypted inside the cluster automatically.

## Step 18 — cert-manager + ClusterIssuers (Cloudflare DNS-01)

Issues Let's Encrypt certificates using your Cloudflare API token. Two `ClusterIssuer` resources: `letsencrypt-production` (real certs) and `letsencrypt-staging` (testing).

The Cloudflare API token is committed SOPS-encrypted at `kubernetes/apps/cert-manager/cert-manager/issuers/secret.sops.yaml`. The `cert-manager-issuers` Flux Kustomization `dependsOn: cert-manager` so it doesn't try to apply CRDs before they exist.

After push:

```bash
kubectl get clusterissuers
# Both should show READY: True
```

## Step 19 — Cloudflare Tunnel (cloudflared)

Cluster's external entry point. No port forward, no exposed home IP. See [cloudflared.md](cloudflared.md) for the full setup.

1. Create a tunnel in Cloudflare Zero Trust dashboard, copy the token
2. SOPS-encrypt the token into `kubernetes/apps/network/cloudflared/app/secret.sops.yaml`
3. Push — Flux deploys 2 replicas of cloudflared with anti-affinity
4. In CF dashboard, add Public Hostname routes (`<app>.wajeht.com → cilium-gateway-internet.kube-system.svc.cluster.local:80`)

## Step 20 — Cilium Gateway + LB IPPool

```
kubernetes/apps/kube-system/cilium-gateway/app/
├── ippool.yaml        # CiliumLoadBalancerIPPool (192.168.4.220-229)
└── gateway.yaml       # Gateway "internet" with HTTP listener on :80
```

The Gateway gets a LoadBalancer Service named `cilium-gateway-internet`. The IP is from our pool but cloudflared talks to it via cluster DNS (`cilium-gateway-internet.kube-system.svc.cluster.local`), so the LB IP doesn't need to be externally routable.

Verify:

```bash
kubectl get gateway -A
# internet  cilium  192.168.4.220  PROGRAMMED=True
```

## Step 21 — Longhorn (block storage)

Required before any stateful app. See [longhorn.md](longhorn.md) for the full deep dive.

1. Add a Talos **UserVolume** patch to `talconfig.yaml` for the data disk (yanlon's `/dev/sda` 1TB SATA in our case):
   ```yaml
   nodes:
     - hostname: yanlon
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
2. `make talos-config && make talos-apply` (live update, no reboot) — Talos partitions/formats/mounts the disk at `/var/mnt/longhorn`
3. Add the Longhorn HelmRelease at `kubernetes/apps/longhorn-system/longhorn/` (chart `1.11.1`, `defaultDataPath=/var/mnt/longhorn`, `defaultReplicaCount=1`)
4. Add a `StorageClass` named `longhorn` with `is-default-class: "true"` annotation
5. Push — Flux installs

Verify:

```bash
kubectl get storageclass         # `longhorn` should show (default)
kubectl -n longhorn-system get pods    # all Running
kubectl get nodes.longhorn.io -A # yanlon listed with available storage
```

## Step 22 — Volsync (PVC backups)

Install the Volsync operator. Per-app backup config (ReplicationSource + destination secret) gets added when each stateful app is migrated. See [volsync.md](volsync.md) for the per-app pattern.

```bash
# Add HelmRelease at kubernetes/apps/volsync-system/volsync/
#   - chart: backube/volsync v0.15.0
#   - manageCRDs: true
git add kubernetes/apps/volsync-system
git commit -m "feat(volsync-system): add volsync operator"
git push
```

Verify after push:

```bash
kubectl -n volsync-system get pods
kubectl get crd | grep volsync
# Should list replicationsources, replicationdestinations, etc.
```

Backup destination not configured yet — that happens with nfs-subdir-external-provisioner next.

## Step 23 — Validate with an echo app

Deploy a minimal echo server + HTTPRoute and hit it from the internet:

- Deployment: `ealen/echo-server` returning JSON of the request
- Service: ClusterIP :80
- HTTPRoute: `echo.wajeht.com` → echo Service, attached to the `internet` Gateway

```bash
curl https://echo.wajeht.com/
# Should return JSON with your CF-Ray, real IP, and pod hostname
```

If it works, every layer in [architecture.md](architecture.md) is proven.

## What's next

Bootstrap so far ✅: Talos · Cilium · Flux · SOPS decryption · metrics-server · reloader · reflector · cert-manager · cloudflared · Cilium Gateway · echo app · Longhorn · Volsync

Remaining stack — same pattern via [adding-apps.md](adding-apps.md):

1. ~~FluxCD~~ ✅ done
2. ~~metrics-server~~ ✅ done
3. ~~reloader~~ ✅ done
4. ~~reflector~~ ✅ done
5. ~~cert-manager + Cloudflare issuer~~ ✅ done
6. ~~cloudflared (tunnel) + Cilium Gateway~~ ✅ done
7. ~~Longhorn~~ ✅ done
8. ~~Volsync~~ ✅ done (operator only; backup destination configured next)
9. **nfs-subdir-external-provisioner** — Synology NFS PVs for backup repo + bulk media
10. **CNPG** — Postgres operator (before any Postgres-backed app)
11. **oauth2-proxy** — Google forward-auth replacement
12. **node-feature-discovery** + **intel-device-plugin** — for Plex transcoding
13. **kube-prometheus-stack** — Prometheus + Grafana + Alertmanager
14. **system-upgrade-controller** — auto Talos/k8s upgrades
15. **external-dns** — only needed when migrating jaw.dev to the cluster (see [architecture.md](architecture.md) for the migration plan)

Plus: **convert Cilium to HelmRelease** so Flux owns it going forward (so future Cilium upgrades = git commit, not `helm upgrade`).

See [kubernetes.md](kubernetes.md) for the full stack and [architecture.md](architecture.md) for how everything ties together.

## Gotchas we learned the hard way

1. **`talosctl reset` defaults to SHUTDOWN, not reboot.** Add `--reboot`. Otherwise nodes power off and you wonder why they don't come back.
2. **`--wipe-mode all` (the default) wipes SYSTEM partition too.** You'll need a USB to reinstall. Use `--system-labels-to-wipe EPHEMERAL,STATE` to preserve the Talos OS install. The Makefile target now does this correctly.
3. **Resets must talk to the target node directly.** If you reset the CP first and then try to reset a worker, your talosctl is now routing through the dead CP endpoint. Use `--endpoints <NODE_IP>` to target the node directly. The Makefile does this.
4. **`cluster.proxy.disabled: true` doesn't remove an existing kube-proxy DaemonSet.** It only prevents creation during bootstrap. If kube-proxy was already running, `kubectl delete daemonset kube-proxy` manually.
5. **Talos's `--insecure` flag is for maintenance mode only.** After `apply-config`, the node has cluster certs and requires authenticated talosctl (uses the talosconfig in `clusterconfig/`).
6. **One USB is enough for the whole cluster.** Talos runs from RAM after boot — pull the USB after the node is up and reuse it for the next node. But be careful: if a node reboots before `apply-config` installs to disk, you'll need the USB back.
7. **The `kubernetes/talos/clusterconfig/` directory is gitignored** — it contains plaintext machine secrets. Don't commit it.
