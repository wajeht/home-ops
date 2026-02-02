#!/bin/bash
# Install Docker and SOPS on fresh VPS
set -e

echo "==> Installing Docker..."
curl -fsSL https://get.docker.com | sh
docker --version

echo "==> Installing SOPS..."
curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops
sops --version

echo "==> Creating directories..."
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops

echo "==> Done!"
echo ""
echo "Next steps:"
echo "  1. Copy age key: scp ~/.sops/age-key.txt root@THIS_VPS:/root/.sops/"
echo "  2. Clone repo:   git clone https://TOKEN@github.com/wajeht/home-ops.git"
echo "  3. Run:          cd home-ops && ./scripts/decrypt-secrets.sh"
echo "  4. Run:          ./scripts/bootstrap.sh"
