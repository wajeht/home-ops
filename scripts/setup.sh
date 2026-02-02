#!/bin/bash
# Full VPS setup - run on fresh Ubuntu server
# Usage: curl -fsSL https://raw.githubusercontent.com/wajeht/home-ops/main/scripts/setup.sh | bash
set -e

echo "=== home-ops VPS Setup ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root"
    exit 1
fi

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "[1/5] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "[1/5] Docker already installed"
fi

# Install SOPS
if ! command -v sops &> /dev/null; then
    echo "[2/5] Installing SOPS..."
    curl -sLO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
    chmod +x /usr/local/bin/sops
else
    echo "[2/5] SOPS already installed"
fi

# Create directories
echo "[3/5] Creating directories..."
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops

# Check for age key
if [ ! -f /root/.sops/age-key.txt ]; then
    echo ""
    echo "=== ACTION REQUIRED ==="
    echo "Copy your age key to this server:"
    echo "  scp ~/.sops/age-key.txt root@$(hostname -I | awk '{print $1}'):/root/.sops/"
    echo ""
    echo "Then run this script again."
    exit 0
fi

# Check if repo exists
if [ ! -d ~/home-ops ]; then
    echo ""
    echo "=== ACTION REQUIRED ==="
    echo "Clone the repo:"
    echo "  git clone https://YOUR_TOKEN@github.com/wajeht/home-ops.git"
    echo ""
    echo "Then run: cd ~/home-ops && ./scripts/setup.sh"
    exit 0
fi

cd ~/home-ops

# Decrypt secrets
echo "[4/5] Decrypting secrets..."
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/webhook-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/cf-token
grep "^ACME_EMAIL=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/acme-email

rm /tmp/secrets.env
chmod 600 /root/.secrets/*

# Bootstrap infrastructure
echo "[5/5] Starting infrastructure..."
docker network inspect traefik >/dev/null 2>&1 || docker network create traefik
cd infrastructure/traefik && docker compose up -d
cd ../doco-cd && docker compose up -d
cd ~/home-ops

echo ""
echo "=== Setup Complete ==="
docker ps --format "table {{.Names}}\t{{.Status}}"
echo ""
echo "Next steps:"
echo "  1. Point DNS *.yourdomain.com to $(hostname -I | awk '{print $1}')"
echo "  2. Add GitHub webhook: https://doco.yourdomain.com/v1/webhook"
echo "  3. Push a commit to test"
