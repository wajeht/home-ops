# K3s

Single-node K3s cluster on the OptiPlex 7070 Micro (`192.168.4.163`).

## What's Included

K3s ships these out of the box — no extra install needed:

| Component              | What it does                                    |
| ---------------------- | ----------------------------------------------- |
| Traefik                | Ingress controller, routes external traffic     |
| Flannel                | CNI, pod-to-pod networking                      |
| CoreDNS                | Cluster DNS                                     |
| ServiceLB              | LoadBalancer for bare-metal (extractly klipper) |
| Local Path Provisioner | PersistentVolume on local disk                  |
| Metrics Server         | `kubectl top` for pods and nodes                |
| SQLite                 | Lightweight datastore (replaces etcd)           |
| containerd             | Container runtime                               |

## Install

On the server:

```bash
curl -sfL https://get.k3s.io | sh -
```

Verify:

```bash
sudo k3s kubectl get nodes
```

## Remote kubectl Access

Copy the kubeconfig from the server:

```bash
sudo cat /etc/rancher/k3s/k3s.yaml
```

On your Mac, save it to `~/.kube/config`. Change the `server` field from `127.0.0.1` to the server IP:

```yaml
server: https://192.168.4.163:6443
```

### Leaf-Only Client Cert Fix

K3s generates a kubeconfig with the full client certificate chain (leaf + CA). Go 1.25's TLS implementation rejects this with `tls: error decoding message`. Strip the CA cert and keep only the leaf:

```bash
# Extract leaf cert only (first cert in the chain)
kubectl config view --raw -o jsonpath='{.users[?(@.name=="k3s-admin")].user.client-certificate-data}' \
  | base64 -d \
  | openssl x509 \
  | base64 \
  | tr -d '\n'
```

Replace `client-certificate-data` in `~/.kube/config` with that output.

### Multiple Clusters

If you have other clusters (e.g. OrbStack), use contexts:

```bash
kubectl config get-contexts          # list all
kubectl config use-context k3s       # switch to k3s
kubectl config use-context orbstack  # switch to orbstack
```

## Common Commands

```bash
kubectl get nodes                    # list nodes
kubectl get pods -A                  # all pods, all namespaces
kubectl get svc -A                   # all services
kubectl top nodes                    # node resource usage
kubectl top pods -A                  # pod resource usage
kubectl logs <pod> -n <namespace>    # pod logs
kubectl describe pod <pod> -n <ns>   # pod details
```

## Architecture

```
                  ┌──────────────────────────────────┐
                  │  OptiPlex 7070 (192.168.4.163)   │
                  │                                  │
  Internet ──▶   │  Traefik (Ingress)               │
                  │    ├── app-a (Pod)               │
                  │    ├── app-b (Pod)               │
                  │    └── app-c (Pod)               │
                  │                                  │
                  │  CoreDNS    Flannel    SQLite    │
                  │  Metrics    ServiceLB            │
                  └──────────────────────────────────┘
                           │
                           │ NFS
                           ▼
                  ┌──────────────────┐
                  │  Synology DS923+ │
                  └──────────────────┘
```

## Next

- Kubernetes concepts: [kubernetes.io/docs](https://kubernetes.io/docs/concepts/)
- K3s docs: [docs.k3s.io](https://docs.k3s.io)
