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
./scripts/setup.sh update-infra        # Pull latest and redeploy docker-cd
./scripts/setup.sh update-infra-force  # Force-recreate docker-cd
./scripts/setup.sh nfs mount           # Mount NFS shares
./scripts/setup.sh nfs persist         # Persist NFS mounts
./scripts/setup.sh sata persist        # Persist SATA mount
./scripts/cloudflare.sh                # Update Cloudflare IP allowlists
```

## Optional OS Tuning

Apply after install if this is a fresh Ubuntu host:

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
