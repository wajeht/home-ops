# Quick Start

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
scp ~/.sops/age-key.txt user@server:~/.sops/
cd ~/home-ops && ./scripts/home-ops.sh install
```

## OS Tuning

Apply after install. Both persist across reboots.

```bash
# Swappiness: 60 (default) → 10
sudo sysctl vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf

# CPU governor: powersave → performance
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
sudo apt-get install -yq cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
```

**Swappiness** — default 60 means Linux aggressively swaps to disk even with free RAM. With 32GB RAM and ~8GB used, swapping wastes SSD bandwidth and adds latency to containers. Setting 10 means only swap when RAM is nearly full.

**CPU governor** — `powersave` throttles CPU to minimum frequency and ramps up on demand, adding latency. `performance` keeps all cores at max (3.6-4.2GHz). Power difference is ~5-10W on a 65W desktop CPU — negligible for a 24/7 server running 53+ containers with ML inference.

## Management

```bash
./scripts/home-ops.sh install        # Deploy everything
./scripts/home-ops.sh uninstall      # Remove all stacks and cleanup
./scripts/home-ops.sh update-infra   # Pull latest and redeploy docker-cd
./scripts/home-ops.sh status         # Show services, mounts, disk usage
./scripts/home-ops.sh nfs mount      # Mount NFS shares
./scripts/home-ops.sh nfs persist    # Add NFS mounts to fstab (survives reboot)
./scripts/home-ops.sh sata persist   # Add SATA mount to fstab (survives reboot)
./scripts/home-ops.sh setup          # Create data directories
```
