# Quick Start

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
scp ~/.sops/age-key.txt user@server:~/.sops/
cd ~/home-ops && ./scripts/home-ops.sh install
```

## Management

```bash
./scripts/home-ops.sh install        # Deploy everything
./scripts/home-ops.sh uninstall      # Remove all stacks and cleanup
./scripts/home-ops.sh update-infra   # Redeploy docker-cd
./scripts/home-ops.sh status         # Show services, mounts, disk usage
./scripts/home-ops.sh nfs mount      # Mount NFS shares
./scripts/home-ops.sh setup          # Create data directories
```
