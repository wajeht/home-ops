#!/bin/bash
# Docker Swarm setup for home-ops
# Usage: ./scripts/setup.sh
set -eo pipefail

echo "=== home-ops Setup ==="

# Config
if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="$HOME"
    SUDO="sudo"
fi
REPO_DIR="$HOME_DIR/home-ops"
export SOPS_AGE_KEY_FILE="$HOME_DIR/.sops/age-key.txt"

# Prerequisites
echo "[1/4] Checking prerequisites..."
[ ! -f "$SOPS_AGE_KEY_FILE" ] && { echo "ERROR: Copy age key: scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$HOME_DIR/.sops/"; exit 1; }
[ ! -d "$REPO_DIR" ] && { echo "ERROR: Clone repo: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"; exit 1; }

# Install Docker
echo "[2/4] Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | $SUDO sh
    [ "$EUID" -ne 0 ] && $SUDO usermod -aG docker "$USER"
fi

# Install SOPS
if ! command -v sops &> /dev/null; then
    $SUDO curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
    $SUDO chmod +x /usr/local/bin/sops
fi

# Init Swarm
echo "[3/4] Swarm..."
$SUDO docker info 2>/dev/null | grep -q "Swarm: active" || \
    $SUDO docker swarm init --advertise-addr "$(hostname -I | awk '{print $1}')"

# Setup
echo "[4/4] Deploying core infra..."
cd "$REPO_DIR"

# Directories
mkdir -p "$HOME_DIR/.sops" "$HOME_DIR/.docker" "$HOME_DIR/plex"/{downloads,movies,tv,music,audiobooks,podcasts}
chmod 700 "$HOME_DIR/.sops"
chown -R 1000:1000 "$HOME_DIR/plex" 2>/dev/null || true

# Network
$SUDO docker network create --driver overlay --attachable traefik 2>/dev/null || true

# GHCR auth
GHCR_TOKEN=$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GHCR_TOKEN=" | cut -d= -f2 || true)
if [ -n "$GHCR_TOKEN" ]; then
    echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$(printf "wajeht:%s" "$GHCR_TOKEN" | base64)\"}}}" > "$HOME_DIR/.docker/config.json"
    chmod 600 "$HOME_DIR/.docker/config.json"
    echo "$GHCR_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin
fi

# Docker secrets
create_secret() {
    local name=$1 value=$2
    [ -z "$value" ] && return
    $SUDO docker secret rm "$name" 2>/dev/null || true
    echo "$value" | $SUDO docker secret create "$name" -
}

create_secret git_access_token "$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2 || true)"
create_secret cf_dns_api_token "$(sops -d infra/traefik/.enc.env 2>/dev/null | grep "^CF_DNS_API_TOKEN=" | cut -d= -f2 || true)"

# Deploy core (doco-cd handles rest)
deploy() {
    local dir=$1 name=$2 registry=${3:-false}
    local flags=""
    [ "$registry" = "true" ] && flags="--with-registry-auth"
    HOME="$HOME_DIR" $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" $flags "$name"
}

deploy infra/traefik traefik
deploy infra/doco-cd doco-cd true

# vpn-qbit (needs docker-compose - swarm doesn't support devices/network_mode)
echo ""
echo "[vpn-qbit] Setting up..."
mkdir -p /dev/net 2>/dev/null || true
[ ! -c /dev/net/tun ] && $SUDO mknod /dev/net/tun c 10 200 && $SUDO chmod 666 /dev/net/tun
cd "$REPO_DIR/apps/vpn-qbit"
sops -d ../media/.enc.env > .env 2>/dev/null || echo "WARN: No VPN credentials"
$SUDO docker compose up -d 2>/dev/null || echo "WARN: vpn-qbit not started"

echo ""
echo "=== Done ==="
$SUDO docker service ls
echo ""
echo "doco-cd will auto-deploy apps within 60s: https://doco.wajeht.com"
echo "DNS: Point *.wajeht.com to $(hostname -I | awk '{print $1}')"
