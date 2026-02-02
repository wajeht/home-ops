#!/bin/bash
# Full server setup for Docker Swarm with per-app SOPS secrets
# Usage: ./scripts/setup.sh
set -e

echo "=== home-ops Setup ==="
echo ""

# Determine home directory and sudo
if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="$HOME"
    SUDO="sudo"
fi

REPO_DIR="$HOME_DIR/home-ops"

# Install Docker
if ! command -v docker &> /dev/null; then
    echo "[1/5] Installing Docker..."
    curl -fsSL https://get.docker.com | $SUDO sh
    [ "$EUID" -ne 0 ] && $SUDO usermod -aG docker $USER
else
    echo "[1/5] Docker installed"
fi

# Install SOPS
if ! command -v sops &> /dev/null; then
    echo "[2/5] Installing SOPS..."
    $SUDO curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    $SUDO chmod +x /usr/local/bin/sops
else
    echo "[2/5] SOPS installed"
fi

# Initialize Docker Swarm
if ! $SUDO docker info 2>/dev/null | grep -q "Swarm: active"; then
    echo "[3/5] Initializing Swarm..."
    $SUDO docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
else
    echo "[3/5] Swarm active"
fi

# Check prerequisites
echo "[4/5] Checking prerequisites..."
mkdir -p $HOME_DIR/.sops && chmod 700 $HOME_DIR/.sops

if [ ! -f $HOME_DIR/.sops/age-key.txt ]; then
    echo "ERROR: Copy age key first:"
    echo "  scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$HOME_DIR/.sops/"
    exit 1
fi

[ ! -d "$REPO_DIR" ] && { echo "ERROR: Clone repo first: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"; exit 1; }

cd "$REPO_DIR"
export SOPS_AGE_KEY_FILE=$HOME_DIR/.sops/age-key.txt

# Setup ghcr.io auth
mkdir -p $HOME_DIR/.docker
GHCR_TOKEN=$(sops -d infrastructure/doco-cd/.enc.env 2>/dev/null | grep "^GHCR_TOKEN=" | cut -d= -f2 || true)
if [ -n "$GHCR_TOKEN" ]; then
    AUTH=$(printf "wajeht:%s" "$GHCR_TOKEN" | base64)
    echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$AUTH\"}}}" > $HOME_DIR/.docker/config.json
    chmod 600 $HOME_DIR/.docker/config.json
    echo "$GHCR_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin
fi

# Deploy stacks
echo "[5/5] Deploying stacks..."
$SUDO docker network create --driver overlay --attachable traefik 2>/dev/null || true

deploy() {
    local dir=$1 name=$2 registry=$3

    # Decrypt .enc.env if exists, source vars
    [ -f "$dir/.enc.env" ] && { eval "$(sops -d "$dir/.enc.env")"; export $(sops -d "$dir/.enc.env" | cut -d= -f1 | xargs); }

    # Deploy
    if [ "$registry" = "true" ]; then
        HOME=$HOME_DIR $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" --with-registry-auth "$name"
    else
        HOME=$HOME_DIR $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" "$name"
    fi
}

deploy infrastructure/traefik traefik
deploy infrastructure/doco-cd doco-cd
deploy apps/homepage homepage
deploy apps/whoami whoami
deploy apps/commit commit true

echo ""
echo "=== Done ==="
$SUDO docker service ls
echo ""
echo "DNS: Point *.wajeht.com to $(hostname -I | awk '{print $1}')"
