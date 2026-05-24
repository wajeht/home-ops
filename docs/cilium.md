# Cilium

CNI + Gateway API + LB IPAM + kube-proxy replacement, all in one. Replaces the trio of (Flannel + kube-proxy + ingress-nginx + MetalLB) that most older homelabs run.

## Prerequisites

Talos cluster must already have:

- `cniConfig: { name: none }` in `talconfig.yaml` (so Talos doesn't install Flannel)
- `cluster.proxy.disabled: true` patch (so bootstrap doesn't install kube-proxy)
- Any existing `kube-proxy` DaemonSet manually deleted (`kubectl -n kube-system delete daemonset kube-proxy`)
- A bootstrapped cluster with `kubectl get nodes` showing nodes (they'll be `NotReady` until Cilium is in)

## Install (one-time manual bootstrap)

This is the **only** manual Cilium install. After this, Flux owns it via `HelmRelease`.

### 1. Install Gateway API CRDs

Cilium's `gatewayAPI.enabled: true` requires the standard Kubernetes Gateway API CRDs:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.3.0/standard-install.yaml
```

### 2. Install Cilium via Helm

```bash
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

### 3. Wait for Cilium agent to be Ready

```bash
until kubectl get pods -n kube-system | grep -E "^cilium-[a-z0-9]{5} " | grep -q "1/1"; do
  sleep 5
done
echo "cilium ready"
```

### 4. Verify

```bash
# Nodes should flip NotReady -> Ready
kubectl get nodes

# CoreDNS should go Pending -> Running
kubectl get pods -n kube-system

# Cilium itself
kubectl -n kube-system get pods -l k8s-app=cilium
```

## What each flag does

| Flag                                                                | Why                                                                                                                                                                                       |
| ------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--version 1.19.3`                                                  | Stable Cilium version; what most homelabs run                                                                                                                                             |
| `ipam.mode=kubernetes`                                              | Use Kubernetes' own pod CIDR allocation (Talos manages it); not Cilium's `cluster-pool` mode                                                                                              |
| `kubeProxyReplacement=true`                                         | Cilium replaces kube-proxy entirely — eBPF-based service routing                                                                                                                          |
| `k8sServiceHost=localhost` + `k8sServicePort=7445`                  | Use **KubePrism** — Talos's built-in localhost API server proxy on every node, port 7445. Required so Cilium can reach the API server without going through a (nonexistent) kube-proxy LB |
| `cgroup.autoMount.enabled=false` + `cgroup.hostRoot=/sys/fs/cgroup` | Talos pre-mounts cgroups; tell Cilium not to mess with them                                                                                                                               |
| `securityContext.capabilities.*`                                    | Talos is hardened (no `cap_add: ALL`); these are the minimum capabilities Cilium agent needs                                                                                              |
| `gatewayAPI.enabled=true`                                           | Enable Cilium's Gateway API controller (replaces ingress-nginx)                                                                                                                           |
| `l2announcements.enabled=true`                                      | Enable Cilium LB IPAM to advertise service IPs on the LAN via L2 (ARP), replacing MetalLB                                                                                                 |
| `hubble.relay.enabled=true` + `hubble.ui.enabled=true`              | Observability — live flow visibility, useful for debugging network policies later                                                                                                         |

## Why these differ from a k3s setup

k3s-based homelabs typically use:

- `k8sServiceHost=127.0.0.1` + `k8sServicePort=6444` (k3s-specific localhost API proxy)
- `ipam.mode=cluster-pool` (k3s default)
- No Talos-specific cgroup / securityContext settings (regular Ubuntu doesn't need them)

We adapt that structure for Talos: KubePrism ports, IPAM mode, and Talos hardening flags.

## Upgrading Cilium

Don't `helm upgrade` manually — once Flux is bootstrapped, it manages Cilium via `kubernetes/apps/cilium/app/helmrelease.yaml` (flat layout, even though the workload runs in `kube-system`). Edit the version there, commit, push, Flux reconciles.

## Convert to HelmRelease (after Flux bootstrap)

Once Flux is running, port this install into a `HelmRelease` so it's GitOps-managed. The values above translate directly into the `values:` block of a Flux `HelmRelease`. Flux will adopt the existing release (revision history continues).

## References

- [Cilium docs: Talos installation](https://docs.cilium.io/en/stable/installation/k8s-install-helm/) (general Helm path)
- [Talos docs: Cilium](https://www.talos.dev/v1.12/kubernetes-guides/network/deploying-cilium/) — Talos-specific values
