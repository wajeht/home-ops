#!/bin/bash
# Full server setup for Docker Swarm
# Usage: ./scripts/setup.sh
set -e

echo "=== home-ops Setup (Swarm Mode) ==="
echo ""

# Determine home directory and if we need sudo
if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="$HOME"
    SUDO="sudo"
fi

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "[1/7] Installing Docker..."
    curl -fsSL https://get.docker.com | $SUDO sh
    if [ "$EUID" -ne 0 ]; then
        $SUDO usermod -aG docker $USER
        echo "NOTE: Log out and back in for docker group to take effect"
    fi
else
    echo "[1/7] Docker already installed"
fi

# Install SOPS
if ! command -v sops &> /dev/null; then
    echo "[2/7] Installing SOPS..."
    $SUDO curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    $SUDO chmod +x /usr/local/bin/sops
else
    echo "[2/7] SOPS already installed"
fi

# Initialize Docker Swarm
if ! $SUDO docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "[3/7] Initializing Docker Swarm..."
    $SUDO docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
else
    echo "[3/7] Docker Swarm already initialized"
fi

# Create directories
echo "[4/7] Creating directories..."
mkdir -p $HOME_DIR/.sops
chmod 700 $HOME_DIR/.sops

# Check for age key
if [ ! -f $HOME_DIR/.sops/age-key.txt ]; then
    echo ""
    echo "=== ACTION REQUIRED ==="
    echo "Copy your age key to this server:"
    echo "  scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$HOME_DIR/.sops/"
    echo ""
    echo "Then run this script again."
    exit 0
fi

# Check if repo exists
REPO_DIR="$HOME_DIR/home-ops"
if [ ! -d "$REPO_DIR" ]; then
    echo ""
    echo "=== ACTION REQUIRED ==="
    echo "Clone the repo:"
    echo "  git clone https://github.com/wajeht/home-ops.git $REPO_DIR"
    echo ""
    echo "Then run: cd $REPO_DIR && ./scripts/setup.sh"
    exit 0
fi

cd "$REPO_DIR"

# Decrypt secrets and create Docker secrets
echo "[5/7] Creating Docker secrets..."
export SOPS_AGE_KEY_FILE=$HOME_DIR/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

# Extract secrets to temp files
grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /tmp/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/cf-token
GHCR_TOKEN=$(grep "^GHCR_TOKEN=" /tmp/secrets.env | cut -d= -f2)

# Create docker config for private registry
AUTH=$(printf "wajeht:%s" "$GHCR_TOKEN" | base64)
echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$AUTH\"}}}" > /tmp/docker-config.json

# Create Docker secrets (remove if exist, then create)
for secret in git_token webhook_secret api_secret apprise_url cf_token sops_age_key docker_config; do
    $SUDO docker secret rm "$secret" 2>/dev/null || true
done

$SUDO docker secret create git_token /tmp/git-token
$SUDO docker secret create webhook_secret /tmp/webhook-secret
$SUDO docker secret create api_secret /tmp/api-secret
$SUDO docker secret create apprise_url /tmp/apprise-url
$SUDO docker secret create cf_token /tmp/cf-token
$SUDO docker secret create sops_age_key $HOME_DIR/.sops/age-key.txt
$SUDO docker secret create docker_config /tmp/docker-config.json

# Login to ghcr for pulling private images
echo "[6/7] Logging into ghcr.io..."
echo "$GHCR_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin

# Cleanup temp files
rm -f /tmp/secrets.env /tmp/git-token /tmp/webhook-secret /tmp/api-secret /tmp/apprise-url /tmp/cf-token /tmp/docker-config.json

# Create overlay network and deploy
echo "[7/7] Deploying stacks..."
$SUDO docker network rm traefik 2>/dev/null || true
$SUDO docker network create --driver overlay --attachable traefik

# Deploy infrastructure
$SUDO docker stack deploy -c infrastructure/traefik/docker-compose.yml traefik
$SUDO docker stack deploy -c infrastructure/doco-cd/docker-compose.yml doco-cd

# Deploy apps
$SUDO docker stack deploy -c apps/homepage/docker-compose.yml homepage
$SUDO docker stack deploy -c apps/whoami/docker-compose.yml whoami
$SUDO docker stack deploy -c apps/commit/docker-compose.yml --with-registry-auth commit

echo ""
echo "=== Setup Complete ==="
echo ""
echo "Swarm status:"
$SUDO docker node ls
echo ""
echo "Secrets:"
$SUDO docker secret ls
echo ""
echo "Services:"
$SUDO docker service ls
echo ""
echo "Next steps:"
echo "  1. Configure DNS to point *.yourdomain.com to $(hostname -I | awk '{print $1}')"
echo "     (Use AdGuard DNS rewrite for local, or public DNS for internet)"
echo "  2. Wait for services to start: watch '$SUDO docker service ls'"
