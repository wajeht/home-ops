#!/bin/bash
# Full VPS setup - run on fresh Ubuntu server
# Usage: curl -fsSL https://raw.githubusercontent.com/wajeht/home-ops/main/scripts/setup.sh | bash
set -e

echo "=== home-ops VPS Setup (Swarm Mode) ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root"
    exit 1
fi

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "[1/6] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
else
    echo "[1/6] Docker already installed"
fi

# Install SOPS
if ! command -v sops &> /dev/null; then
    echo "[2/6] Installing SOPS..."
    curl -sLO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
    chmod +x /usr/local/bin/sops
else
    echo "[2/6] SOPS already installed"
fi

# Initialize Docker Swarm
if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "[3/6] Initializing Docker Swarm..."
    docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
else
    echo "[3/6] Docker Swarm already initialized"
fi

# Create directories
echo "[4/6] Creating directories..."
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

# Decrypt secrets and create Docker secrets
echo "[5/6] Creating Docker secrets..."
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

# Extract secrets to temp files
grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /tmp/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/cf-token

# Create Docker secrets (remove if exist, then create)
for secret in git_token webhook_secret api_secret apprise_url cf_token sops_age_key; do
    docker secret rm "$secret" 2>/dev/null || true
done

docker secret create git_token /tmp/git-token
docker secret create webhook_secret /tmp/webhook-secret
docker secret create api_secret /tmp/api-secret
docker secret create apprise_url /tmp/apprise-url
docker secret create cf_token /tmp/cf-token
docker secret create sops_age_key /root/.sops/age-key.txt

# Cleanup temp files
rm -f /tmp/secrets.env /tmp/git-token /tmp/webhook-secret /tmp/api-secret /tmp/apprise-url /tmp/cf-token

# Create overlay network
echo "[6/6] Starting infrastructure..."
docker network rm traefik 2>/dev/null || true
docker network create --driver overlay --attachable traefik

# Deploy stacks
cd infrastructure/traefik && docker stack deploy -c docker-compose.yml traefik
cd ../doco-cd && docker stack deploy -c docker-compose.yml doco-cd
cd ~/home-ops

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Swarm status:"
docker node ls
echo ""
echo "Secrets:"
docker secret ls
echo ""
echo "Services:"
docker service ls
echo ""
echo "Next steps:"
echo "  1. Point DNS *.yourdomain.com to $(hostname -I | awk '{print $1}')"
echo "  2. Add GitHub webhook: https://doco.yourdomain.com/v1/webhook"
echo "  3. Push a commit to test rolling updates"
