#!/bin/bash
# home-ops management script
# Usage: ./scripts/home-ops.sh <command> [args]
set -eo pipefail

# Config
if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="${HOME:-/home/jaw}"
    SUDO="sudo"
fi
REPO_DIR="$HOME_DIR/home-ops"
export SOPS_AGE_KEY_FILE="$HOME_DIR/.sops/age-key.txt"

# NFS config
NAS_IP="192.168.4.160"
NFS_MOUNTS=(
    "plex|/volume1/plex|$HOME_DIR/plex"
    "backup|/volume1/backup|$HOME_DIR/backup/kopia"
)

# Data directories
DATA_DIRS=(
    "$HOME_DIR/data/audiobookshelf/config"
    "$HOME_DIR/data/audiobookshelf/metadata"
    "$HOME_DIR/data/authelia"
    "$HOME_DIR/data/bang"
    "$HOME_DIR/data/calendar"
    "$HOME_DIR/data/changedetection"
    "$HOME_DIR/data/close-powerlifting"
    "$HOME_DIR/data/doco-cd"
    "$HOME_DIR/data/favicon"
    "$HOME_DIR/data/gains"
    "$HOME_DIR/data/gitea"
    "$HOME_DIR/data/gluetun"
    "$HOME_DIR/data/kopia/config"
    "$HOME_DIR/data/kopia/cache"
    "$HOME_DIR/data/kopia/logs"
    "$HOME_DIR/data/kopia/dumps"
    "$HOME_DIR/data/linx/files"
    "$HOME_DIR/data/linx/meta"
    "$HOME_DIR/data/media/plex"
    "$HOME_DIR/data/media/prowlarr"
    "$HOME_DIR/data/media/radarr"
    "$HOME_DIR/data/media/sonarr"
    "$HOME_DIR/data/media/tautulli"
    "$HOME_DIR/data/media/overseerr"
    "$HOME_DIR/data/miniflux/db"
    "$HOME_DIR/data/mm2us"
    "$HOME_DIR/data/notify"
    "$HOME_DIR/data/ntfy"
    "$HOME_DIR/data/qbittorrent"
    "$HOME_DIR/data/screenshot"
    "$HOME_DIR/data/stirling-pdf"
    "$HOME_DIR/data/traefik/certs"
    "$HOME_DIR/data/uptime-kuma"
    "$HOME_DIR/data/vaultwarden"
    "$HOME_DIR/plex/downloads"
    "$HOME_DIR/plex/movies"
    "$HOME_DIR/plex/tv"
    "$HOME_DIR/plex/music"
    "$HOME_DIR/plex/audiobooks"
    "$HOME_DIR/plex/podcasts"
    "$HOME_DIR/backup/kopia"
    "$HOME_DIR/.sops"
    "$HOME_DIR/.docker"
)

#=============================================================================
# SETUP - Create directories
#=============================================================================
cmd_setup() {
    echo "=== Creating directories ==="
    for dir in "${DATA_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo "  Created: $dir"
        fi
    done
    mkdir -p /tmp/kopia 2>/dev/null || true
    chmod 700 "$HOME_DIR/.sops" 2>/dev/null || true
    chown -R 1000:1000 "$HOME_DIR/plex" "$HOME_DIR/data" 2>/dev/null || true
    echo "Done."
}

#=============================================================================
# NFS - Mount/unmount NFS shares
#=============================================================================
nfs_mount() {
    local name=$1 nas_path=$2 local_path=$3
    if mountpoint -q "$local_path" 2>/dev/null; then
        echo "$name: Already mounted"
        return
    fi
    echo "Mounting $name: $NAS_IP:$nas_path -> $local_path"
    mkdir -p "$local_path"
    $SUDO mount -t nfs "$NAS_IP:$nas_path" "$local_path" && echo "  OK" || echo "  FAILED"
}

nfs_unmount() {
    local name=$1 nas_path=$2 local_path=$3
    echo "Unmounting $name: $local_path"
    $SUDO umount "$local_path" 2>/dev/null && echo "  OK" || echo "  Not mounted"
}

nfs_status() {
    local name=$1 nas_path=$2 local_path=$3
    if mountpoint -q "$local_path" 2>/dev/null; then
        printf "%-10s MOUNTED   " "$name:"
        df -h "$local_path" | awk 'NR==2 {print $3"/"$2" ("$5" used)"}'
    else
        echo "$name:    NOT MOUNTED"
    fi
}

cmd_nfs() {
    local action=$1 target=${2:-all}
    [ -z "$action" ] && { echo "Usage: $0 nfs {mount|unmount|status} [plex|backup|all]"; exit 1; }

    for mount in "${NFS_MOUNTS[@]}"; do
        IFS='|' read -r name nas_path local_path <<< "$mount"
        if [[ "$target" == "all" || "$target" == "$name" ]]; then
            case "$action" in
                mount) nfs_mount "$name" "$nas_path" "$local_path" ;;
                unmount|umount) nfs_unmount "$name" "$nas_path" "$local_path" ;;
                status) nfs_status "$name" "$nas_path" "$local_path" ;;
            esac
        fi
    done
}

#=============================================================================
# INSTALL - Deploy swarm stacks
#=============================================================================
cmd_install() {
    echo "=== home-ops Install ==="

    # Prerequisites
    echo "[1/5] Checking prerequisites..."
    [ ! -f "$SOPS_AGE_KEY_FILE" ] && { echo "ERROR: Copy age key: scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$HOME_DIR/.sops/"; exit 1; }
    [ ! -d "$REPO_DIR" ] && { echo "ERROR: Clone repo: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"; exit 1; }

    # Install Docker
    echo "[2/5] Docker..."
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
    echo "[3/5] Swarm..."
    $SUDO docker info 2>/dev/null | grep -q "Swarm: active" || \
        $SUDO docker swarm init --advertise-addr "$(hostname -I | awk '{print $1}')"

    # Setup directories
    echo "[4/5] Directories..."
    cmd_setup

    # Create traefik network
    $SUDO docker network create --driver overlay --attachable traefik 2>/dev/null || true

    # Registry auth
    cd "$REPO_DIR"
    DH_USER=$(sops -d infra/.enc.env 2>/dev/null | grep "^DOCKER_HUB_USER=" | cut -d= -f2 || true)
    DH_TOKEN=$(sops -d infra/.enc.env 2>/dev/null | grep "^DOCKER_HUB_TOKEN=" | cut -d= -f2 || true)
    GH_TOKEN=$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GH_TOKEN=" | cut -d= -f2 || true)

    [ -n "$DH_TOKEN" ] && echo "$DH_TOKEN" | $SUDO docker login -u "$DH_USER" --password-stdin
    [ -n "$GH_TOKEN" ] && echo "$GH_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin

    # Copy docker config
    if [ "$EUID" -ne 0 ]; then
        $SUDO mkdir -p /root/.docker /root/.sops
        $SUDO cp /root/.docker/config.json "$HOME_DIR/.docker/config.json" 2>/dev/null || true
        $SUDO cp "$HOME_DIR/.sops/age-key.txt" /root/.sops/
    fi
    chmod 600 "$HOME_DIR/.docker/config.json" 2>/dev/null || true

    # Docker secrets
    echo "[5/5] Deploying..."
    create_secret() {
        local name=$1 value=$2
        [ -z "$value" ] && return
        if $SUDO docker secret inspect "$name" &>/dev/null; then
            echo "  Secret $name exists, skipping"
            return
        fi
        echo "$value" | $SUDO docker secret create "$name" -
    }

    create_secret gh_token "$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^GH_TOKEN=" | cut -d= -f2 || true)"
    create_secret webhook_secret "$(sops -d infra/doco-cd/.enc.env 2>/dev/null | grep "^WEBHOOK_SECRET=" | cut -d= -f2 || true)"
    create_secret cf_dns_api_token "$(sops -d infra/traefik/.enc.env 2>/dev/null | grep "^CF_DNS_API_TOKEN=" | cut -d= -f2 || true)"
    create_secret authelia_jwt_secret "$(sops -d infra/authelia/.enc.env 2>/dev/null | grep "^JWT_SECRET=" | cut -d= -f2 || true)"
    create_secret authelia_session_secret "$(sops -d infra/authelia/.enc.env 2>/dev/null | grep "^SESSION_SECRET=" | cut -d= -f2 || true)"
    create_secret authelia_storage_encryption_key "$(sops -d infra/authelia/.enc.env 2>/dev/null | grep "^STORAGE_ENCRYPTION_KEY=" | cut -d= -f2 || true)"
    create_secret kopia_password "$(sops -d infra/kopia/.enc.env 2>/dev/null | grep "^KOPIA_PASSWORD=" | cut -d= -f2 || true)"

    # Deploy stacks
    deploy() {
        local dir=$1 name=$2
        HOME="$HOME_DIR" $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" --with-registry-auth "$name"
    }

    deploy infra/traefik traefik
    deploy infra/authelia authelia
    deploy infra/kopia kopia
    deploy infra/doco-cd doco-cd

    # vpn-qbit (docker-compose, not swarm)
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
}

#=============================================================================
# UNINSTALL - Remove all stacks
#=============================================================================
cmd_uninstall() {
    echo "=== home-ops Uninstall ==="
    echo "This will remove ALL stacks, secrets, configs, and prune images."
    read -p "Continue? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

    # Stop vpn-qbit
    echo "[1/6] Stopping vpn-qbit..."
    cd "$REPO_DIR/apps/vpn-qbit" 2>/dev/null && $SUDO docker compose down -v 2>/dev/null || true
    cd "$HOME_DIR"

    echo "[2/6] Removing stacks..."
    for stack in $($SUDO docker stack ls --format '{{.Name}}'); do
        echo "  Removing $stack..."
        $SUDO docker stack rm "$stack" 2>/dev/null || true
    done

    echo "[3/6] Waiting for services to stop..."
    sleep 10
    timeout=60
    while [ "$($SUDO docker service ls -q 2>/dev/null | wc -l)" -gt 0 ] && [ $timeout -gt 0 ]; do
        echo "  Waiting... ($timeout s remaining)"
        sleep 5
        timeout=$((timeout - 5))
    done

    echo "[4/6] Removing secrets and configs..."
    $SUDO docker secret ls -q 2>/dev/null | xargs -r $SUDO docker secret rm 2>/dev/null || true
    $SUDO docker config ls -q 2>/dev/null | xargs -r $SUDO docker config rm 2>/dev/null || true

    echo "[5/6] Removing networks..."
    for i in 1 2 3; do
        $SUDO docker network prune -f 2>/dev/null || true
        $SUDO docker network rm traefik 2>/dev/null || true
        sleep 2
    done

    echo "[6/6] Pruning images..."
    $SUDO docker image prune -af 2>/dev/null || true
    $SUDO docker system prune -af 2>/dev/null || true

    echo ""
    echo "=== Done ==="
    cmd_status
}

#=============================================================================
# STATUS - Show current status
#=============================================================================
cmd_status() {
    echo "=== Status ==="
    echo ""
    echo "Services:"
    $SUDO docker service ls 2>/dev/null || echo "  None"
    echo ""
    echo "NFS Mounts:"
    cmd_nfs status
    echo ""
    echo "Disk:"
    df -h "$HOME_DIR/data" "$HOME_DIR/plex" 2>/dev/null | tail -n +2 || true
}

#=============================================================================
# MAIN
#=============================================================================
case "${1:-}" in
    setup)
        cmd_setup
        ;;
    nfs)
        shift
        cmd_nfs "$@"
        ;;
    install)
        cmd_install
        ;;
    uninstall)
        cmd_uninstall
        ;;
    status)
        cmd_status
        ;;
    *)
        echo "home-ops management script"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "Commands:"
        echo "  setup                    Create all data directories"
        echo "  nfs mount [target]       Mount NFS shares (plex|backup|all)"
        echo "  nfs unmount [target]     Unmount NFS shares"
        echo "  nfs status               Show NFS mount status"
        echo "  install                  Deploy all swarm stacks"
        echo "  uninstall                Remove all stacks and cleanup"
        echo "  status                   Show services, mounts, disk usage"
        echo ""
        echo "Examples:"
        echo "  $0 setup                 # Create directories"
        echo "  $0 nfs mount             # Mount all NFS shares"
        echo "  $0 nfs mount plex        # Mount only plex"
        echo "  $0 install               # Deploy everything"
        echo "  $0 status                # Show status"
        exit 1
        ;;
esac
