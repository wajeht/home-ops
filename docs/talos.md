# Talos Linux

## Image Factory

Custom Talos images built via [Image Factory](https://factory.talos.dev/).

**Schematic ID:** `249d9135de54962744e917cfe654117000cba369f9152fbab9d055a00aa3664f`

**Version:** v1.12.6

> The schematic ID is derived from the extension list (and any extra kernel args). Any edit to `talconfig.yaml`'s `systemExtensions` produces a _different_ schematic — see [Changing extensions requires upgrade, not apply](#changing-extensions-requires-upgrade-not-apply).

### Extensions

- `siderolabs/i915` — Intel GPU microcode + kernel modules
- `siderolabs/intel-ucode` — Intel CPU microcode
- `siderolabs/iscsi-tools` — required for Longhorn
- `siderolabs/util-linux-tools` — required for Longhorn / NFS clients
- ~~`siderolabs/nut-client`~~ — **commented out** in talconfig.yaml. UPS monitoring against CyberPower 1500VA. See [Known issues](#known-issues--gotchas) for why and how to re-enable safely.

### Flash USB

```bash
curl -LO https://factory.talos.dev/image/249d9135de54962744e917cfe654117000cba369f9152fbab9d055a00aa3664f/v1.12.6/metal-amd64.iso
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

> **Exception:** if your edit changed the `systemExtensions` list (or anything else baked into the image — kernel args, custom installer args), see [Changing extensions requires upgrade, not apply](#changing-extensions-requires-upgrade-not-apply) below. `apply` won't switch images.

### Changing extensions requires `upgrade`, not `apply`

`apply` writes a new machine config to a running node. It does **not** swap the Talos installer image. The image is locked to a schematic ID, and the schematic ID is a hash of the extension list (+ extra kernel args). When you edit `systemExtensions` and run `talhelper genconfig`, the resulting machineconfig points at a _new_ installer image URL — but the node is still booted off the old one. A bare `apply` will succeed but the actual extensions don't change until reboot, and the new image is never pulled.

Correct flow:

```bash
# 1. Edit talconfig.yaml (add/remove an extension)
$EDITOR talconfig.yaml

# 2. Regenerate configs — talhelper computes the new schematic ID + installer URL
talhelper genconfig

# 3. Compare old vs new installer URL — should differ
grep "image: factory.talos.dev" clusterconfig/*.yaml | head -2

# 4. Run the upgrade (downloads new image, reboots each node into it)
talhelper gencommand upgrade | bash

# 5. After both nodes are Ready again, verify extensions
talosctl --nodes 192.168.4.162,192.168.4.163 get extensions
```

The upgrade command sequence is per-node and serial. With only one CP (soapwa), upgrading it causes ~2-3min of kube-apiserver downtime — apps already running keep serving traffic if cloudflared replicas are healthy on the other node. Workloads on the upgraded node briefly reschedule.

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

## Known issues / gotchas

### Extension without an `ExtensionServiceConfig` → ~72-minute reboot loop

An _officialExtension_ that ships its own service (e.g. `siderolabs/nut-client`) sits in `Waiting for extension service config` until you give it one via an `ExtensionServiceConfig` resource. Talos's boot sequence has a global deadline (~70min by default) and will not declare `RUNNING` until all configured services are `up`. When the deadline expires, Talos logs `boot sequence: failed` and reboots — and the cycle repeats indefinitely.

**Symptoms:**

- Both nodes reboot at near-exact ~71–72min intervals (different start times per node, but identical period within a node)
- `talosctl service ext-nut-client` (or similar) shows `STATE Waiting   EVENT [Waiting]: Waiting for extension service config`
- `talosctl read /var/log/machined.log | grep -i "boot sequence"` shows `boot sequence: failed`
- `/proc/uptime` is always < ~72 min when you check

**How to confirm a node is in the loop:**

```bash
# Find every boot in this Talos install's history (kernel.log is persistent)
talosctl --nodes <IP> read /var/log/kernel.log | grep "Booting paravirtualized kernel" | tail -10
# Look for ~72min intervals between consecutive boot timestamps
```

**Fix:** either remove the extension from `talconfig.yaml`'s `systemExtensions`, or commit an `ExtensionServiceConfig` that satisfies it. Then follow [Changing extensions requires upgrade, not apply](#changing-extensions-requires-upgrade-not-apply) — `apply` alone won't help because the offending extension is baked into the running image.

For `nut-client` specifically, the config needs the NUT server hostname + UPS name + credentials; the NUT server can be the Synology DSM "UPS Service" (Settings → Hardware & Power → UPS → enable network UPS server). Wire that up first, _then_ uncomment the extension in `talconfig.yaml` and `talhelper gencommand upgrade | bash`.

### Reset defaults to _shutdown_, not reboot

`talosctl reset --graceful=false` without `--reboot` powers the node off and you wonder why it's not coming back. Always pass `--reboot` unless you actually want a power-off.

### Reset's default `--wipe-mode all` nukes the OS install

Without `--system-labels-to-wipe EPHEMERAL,STATE`, the reset wipes the Talos installer too and the node needs a USB reinstall. Use the targeted wipe (EPHEMERAL = container data, STATE = machine config) for routine resets.
