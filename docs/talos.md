# Talos Linux

## Image Factory

Custom Talos images built via [Image Factory](https://factory.talos.dev/).

**Schematic ID:** `cd0648ed93c7bcf5c362fa0dc72ca43e9e0c0eccf8d46413b6aa35ee71c6c55c`

**Version:** v1.12.6

### Extensions

- `siderolabs/i915` — Intel GPU microcode + kernel modules
- `siderolabs/intel-ucode` — Intel CPU microcode
- `siderolabs/iscsi-tools` — required for Longhorn
- `siderolabs/util-linux-tools` — required for Longhorn
- `siderolabs/nut-client` — UPS monitoring (CyberPower 1500VA)

### Flash USB

```bash
curl -LO https://factory.talos.dev/image/cd0648ed93c7bcf5c362fa0dc72ca43e9e0c0eccf8d46413b6aa35ee71c6c55c/v1.12.6/metal-amd64.iso
```

Flash with Balena Etcher or `dd`. Boot target machine from USB via F12.

## Prerequisites

```bash
brew install siderolabs/tap/talosctl talhelper sops age
```

## Cluster

| Node   | IP            | Role            | Hardware                                             |
| ------ | ------------- | --------------- | ---------------------------------------------------- |
| soapwa | 192.168.4.162 | Control Plane   | OptiPlex 5050, i7-6700, 32GB, 1TB SATA               |
| yanlon | 192.168.4.163 | Worker          | OptiPlex 7070, i7-9700T, 32GB, 256GB NVMe + 1TB SATA |
| apollo | 192.168.4.161 | Worker (future) | OptiPlex 7050, i7-7700, 32GB, 1TB NVMe + 1TB SATA    |

## File Structure

```
kubernetes/talos/
├── talconfig.yaml          # cluster definition (committed)
├── talsecret.sops.yaml     # encrypted secrets (committed)
└── clusterconfig/          # generated configs (gitignored)
    ├── home-cluster-soapwa.yaml
    ├── home-cluster-yanlon.yaml
    └── talosconfig
```

## Setup (from scratch)

All commands run from `kubernetes/talos/` directory.

### 1. Generate secrets

```bash
talhelper gensecret > talsecret.sops.yaml
sops -e -i talsecret.sops.yaml
```

### 2. Define cluster in talconfig.yaml

See `kubernetes/talos/talconfig.yaml` for the full config.

### 3. Generate machine configs

```bash
talhelper genconfig
```

### 4. Boot node from Talos USB

1. Flash ISO to USB (Balena Etcher)
2. Boot target machine from USB (F12 at Dell splash)
3. Node enters Talos maintenance mode, gets DHCP IP
4. Assign fixed IP in UniFi (Network -> Client Devices -> Fixed IP)

### 5. Apply configs

```bash
# First-time apply (nodes in maintenance mode — no TLS/auth yet)
talhelper gencommand apply --extra-flags=--insecure | bash

# After cluster is configured, normal apply works:
talhelper gencommand apply | bash

# Apply to one node only
talhelper gencommand apply --node soapwa | bash
```

> Use `--extra-flags=--insecure` when a node is in maintenance mode (fresh boot or post-reset). Once it has a config + cluster certs, drop the flag.

### 6. Bootstrap cluster (once, first control plane only)

```bash
talhelper gencommand bootstrap | bash
```

### 7. Get kubeconfig

```bash
talosctl kubeconfig --nodes 192.168.4.162
```

### 8. Verify

```bash
kubectl get nodes -o wide
```

## Tool Cheatsheet

Two tools, different jobs:

**talhelper** — config management (define, generate, apply, upgrade):

```bash
talhelper genconfig                                            # generate configs from talconfig.yaml
talhelper gencommand apply | bash                              # apply to already-configured nodes
talhelper gencommand apply --extra-flags=--insecure | bash     # apply to maintenance-mode nodes (first-time or post-reset)
talhelper gencommand apply --node soapwa | bash                # apply to one node
talhelper gencommand bootstrap | bash                          # bootstrap cluster (once)
talhelper gencommand upgrade | bash                            # upgrade Talos version
talhelper gencommand upgrade-k8s | bash                        # upgrade Kubernetes version
talhelper gensecret > talsecret.sops.yaml                      # generate new cluster secrets
```

**talosctl** — day-to-day operations (inspect, debug, interact):

```bash
talosctl dashboard --nodes 192.168.4.162     # live dashboard (CPU, mem, logs)
talosctl health --nodes 192.168.4.162        # health check
talosctl kubeconfig --nodes 192.168.4.162    # get kubeconfig
talosctl get disks --nodes <IP>              # list disks
talosctl get systemdisk --nodes <IP>         # check boot disk
talosctl dmesg --nodes <IP>                  # kernel logs
talosctl logs <service> --nodes <IP>         # service logs (etcd, kubelet, etc)
talosctl reset --nodes <IP> --endpoints <IP> \
    --graceful=false --reboot \
    --system-labels-to-wipe EPHEMERAL,STATE   # wipe data, keep Talos OS, reboot
talosctl get members                         # list cluster members
```

**kubectl** — Kubernetes operations:

```bash
kubectl get nodes -o wide                    # list nodes
kubectl get pods -A                          # all pods
kubectl top nodes                            # node resource usage
```

## Day 2 Operations

### Change cluster config

Edit `talconfig.yaml`, then:

```bash
talhelper genconfig
talhelper gencommand apply | bash
```

### Upgrade Talos

Update `talosVersion` in `talconfig.yaml`, then:

```bash
talhelper genconfig
talhelper gencommand upgrade | bash
```

### Upgrade Kubernetes

Update `kubernetesVersion` in `talconfig.yaml`, then:

```bash
talhelper genconfig
talhelper gencommand upgrade-k8s | bash
```

### Add a new worker (e.g. apollo)

1. Uncomment/add node in `talconfig.yaml`
2. `talhelper genconfig`
3. Flash Talos USB, boot node from USB (F12)
4. `talhelper gencommand apply --node apollo | bash`
5. Verify: `kubectl get nodes`

### Start fresh (whole cluster from scratch)

1. `cd kubernetes/talos/`
2. `talhelper gensecret > talsecret.sops.yaml`
3. `sops -e -i talsecret.sops.yaml`
4. `talhelper genconfig`
5. Boot all nodes from Talos USB
6. `talhelper gencommand apply --extra-flags=--insecure | bash` (insecure = nodes are in maintenance mode)
7. `talhelper gencommand bootstrap | bash`
8. `talosctl kubeconfig --nodes 192.168.4.162`
9. `kubectl get nodes`

### Reset a node

```bash
talosctl reset --nodes <NODE_IP> --endpoints <NODE_IP> \
    --graceful=false --reboot \
    --system-labels-to-wipe EPHEMERAL,STATE
```

Flags explained:

- `--graceful=false` — don't try to cordon/drain (we're wiping, no point)
- `--reboot` — power back on after wipe (default is shut down — surprise gotcha)
- `--system-labels-to-wipe EPHEMERAL,STATE` — wipe only data + config partitions, keep the Talos OS install. Otherwise default `--wipe-mode all` nukes everything and you'd need a USB to reinstall.
- `--endpoints <NODE_IP>` — talk directly to the target node (don't route through the cluster CP, which may itself be wiped/down)

### Check what disks a node has (before installing)

```bash
talosctl get disks --nodes <IP> --insecure    # in maintenance mode
talosctl get disks --nodes <IP>               # after config applied
```

## BIOS Notes

- **SATA Operation** must be set to **AHCI** (not RAID On) for NVMe drives to be detected
- Boot from USB via **F12** at Dell splash
- BIOS setup via **F2**
