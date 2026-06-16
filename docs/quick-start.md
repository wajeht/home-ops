# Quick Start

Use this when rebuilding or bootstrapping the server. It gets the repo, SOPS key, mounts, directories, Docker, and docker-cd into place.

For daily operations, use the script help:

```bash
./scripts/setup.sh help
```

## Bootstrap

On the server:

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
mkdir -p ~/.sops
```

From your Mac:

```bash
scp ~/.sops/age-key.txt user@server:~/.sops/
```

Back on the server:

```bash
cd ~/home-ops
./scripts/setup.sh install
```

## Verify

```bash
./scripts/setup.sh status
./scripts/lint.sh
```

docker-cd should start first, then deploy the rest of `apps/*`.

## Common Commands

```bash
./scripts/setup.sh update        # Pull latest and redeploy docker-cd
./scripts/setup.sh update-force  # Force-recreate docker-cd
./scripts/setup.sh nfs mount     # Mount NFS shares
./scripts/setup.sh nfs persist   # Persist NFS mounts
./scripts/cloudflare.sh          # Update Cloudflare IP allowlists
```

## OS Tuning

Apply after install on a fresh Ubuntu host. These are host-level performance defaults for the Docker server.

| Setting            | What it does                                                                    | Why we use it                                                 |
| ------------------ | ------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `vm.swappiness=10` | Makes Linux avoid swap until memory pressure is real                            | Keeps containers responsive and avoids unnecessary SSD writes |
| CPU `performance`  | Keeps CPU frequency high instead of slowly ramping up from low-power idle modes | Reduces latency for many small container requests             |

Skip this on laptops or power-sensitive hosts. For this always-on OptiPlex, the power cost is small and the latency behavior is better.

```bash
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sudo apt-get install -yq cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
```

## Next

- Add services: [Adding Apps](adding-apps.md)
- Secrets: [Secrets](secrets.md)
- Security: [Security](security.md)
- Recovery: [Disaster Recovery](disaster-recovery.md)
