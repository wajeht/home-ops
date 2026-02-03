#!/bin/bash
# Docker Swarm setup for home-ops
# Usage: ./scripts/install.sh
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
mkdir -p "$HOME_DIR/backup"
mkdir -p "$HOME_DIR/data"/{audiobookshelf/{config,metadata},changedetection,doco-cd,favicon,gitea,gluetun}
mkdir -p "$HOME_DIR/data"/{linx/{files,meta},media/{plex,prowlarr,radarr,sonarr,tautulli,overseerr}}
mkdir -p "$HOME_DIR/data"/{miniflux/db,ntfy,qbittorrent,screenshot,stirling-pdf}
mkdir -p "$HOME_DIR/data"/{traefik/certs,uptime-kuma,vaultwarden}
chmod 700 "$HOME_DIR/.sops"
chown -R 1000:1000 "$HOME_DIR/plex" "$HOME_DIR/data" 2>/dev/null || true

# Create traefik network (external, shared by all stacks)
$SUDO docker network create --driver overlay --attachable traefik 2>/dev/null || true

# Registry auth (Docker Hub + GHCR)
DH_USER=$(sops -d infra/.enc.env 2>/dev/null | grep "^DOCKER_HUB_USER=" | cut -d= -f2 || true)
DH_TOKEN=$(sops -d infra/.enc.env 2>/dev/null | grep "^DOCKER_HUB_TOKEN=" | cut -d= -f2 || true)
GH_TOKEN=$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GH_TOKEN=" | cut -d= -f2 || true)

# Login to registries (creates ~/.docker/config.json with both auths)
[ -n "$DH_TOKEN" ] && echo "$DH_TOKEN" | $SUDO docker login -u "$DH_USER" --password-stdin
[ -n "$GH_TOKEN" ] && echo "$GH_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin

# Copy docker config to /root for swarm and to user home
if [ "$EUID" -ne 0 ]; then
    $SUDO mkdir -p /root/.docker /root/.sops
    $SUDO cp /root/.docker/config.json "$HOME_DIR/.docker/config.json" 2>/dev/null || true
    $SUDO cp "$HOME_DIR/.sops/age-key.txt" /root/.sops/
fi
chmod 600 "$HOME_DIR/.docker/config.json" 2>/dev/null || true

# Docker secrets
create_secret() {
    local name=$1 value=$2
    [ -z "$value" ] && return
    $SUDO docker secret rm "$name" 2>/dev/null || true
    echo "$value" | $SUDO docker secret create "$name" -
}

create_secret gh_token "$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GH_TOKEN=" | cut -d= -f2 || true)"
create_secret webhook_secret "$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^WEBHOOK_SECRET=" | cut -d= -f2 || true)"
create_secret cf_dns_api_token "$(sops -d infra/traefik/.enc.env 2>/dev/null | grep "^CF_DNS_API_TOKEN=" | cut -d= -f2 || true)"

# Deploy core (doco-cd handles rest)
deploy() {
    local dir=$1 name=$2 registry=${3:-false}
    local flags=""
    [ "$registry" = "true" ] && flags="--with-registry-auth"
    HOME="$HOME_DIR" $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" $flags "$name"
}

# Deploy with registry auth for all stacks (needed to pull images)
deploy infra/traefik traefik true
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
