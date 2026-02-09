#!/bin/bash
# home-ops management script
# Usage: ./scripts/home-ops.sh <command> [args]
set -eo pipefail

# Don't run as root - script uses sudo internally
[ "$EUID" -eq 0 ] && { echo "ERROR: Don't run with sudo. Script uses sudo internally."; exit 1; }

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Helpers
info()  { echo -e "${BLUE}${BOLD}::${NC} $*"; }
ok()    { echo -e "${GREEN}${BOLD}ok${NC} $*"; }
warn()  { echo -e "${YELLOW}${BOLD}warn${NC} $*"; }
err()   { echo -e "${RED}${BOLD}err${NC} $*"; }
step()  { echo -e "\n${CYAN}${BOLD}[$1]${NC} $2"; }
header(){ echo -e "\n${BOLD}━━━ $* ━━━${NC}"; }
dim()   { echo -e "${DIM}  $*${NC}"; }

# Config
USER_HOME="/home/jaw"
SUDO="sudo"
REPO_DIR="$USER_HOME/home-ops"
export SOPS_AGE_KEY_FILE="$USER_HOME/.sops/age-key.txt"

# NFS config
NAS_IP="192.168.4.160"
NFS_MOUNTS=(
    "plex|/volume1/plex|$USER_HOME/plex"
    "backup|/volume1/backup|$USER_HOME/backup"
)

# Data directories
DATA_DIRS=(
    "$USER_HOME/data/audiobookshelf/config"
    "$USER_HOME/data/audiobookshelf/metadata"
    "$USER_HOME/data/authelia"
    "$USER_HOME/data/bang"
    "$USER_HOME/data/calendar"
    "$USER_HOME/data/changedetection"
    "$USER_HOME/data/close-powerlifting"
    "$USER_HOME/data/docker-cd"
    "$USER_HOME/data/dozzle"
    "$USER_HOME/data/favicon"
    "$USER_HOME/data/gains"
    "$USER_HOME/data/gitea"
    "$USER_HOME/data/gluetun"
    "$USER_HOME/data/linx/files"
    "$USER_HOME/data/linx/meta"
    "$USER_HOME/data/plex"
    "$USER_HOME/data/jellyfin"
    "$USER_HOME/data/prowlarr"
    "$USER_HOME/data/radarr"
    "$USER_HOME/data/sonarr"
    "$USER_HOME/data/tautulli"
    "$USER_HOME/data/overseerr"
    "$USER_HOME/data/paperless/data"
    "$USER_HOME/data/paperless/media"
    "$USER_HOME/data/paperless/consume"
    "$USER_HOME/data/paperless/db"
    "$USER_HOME/data/paperless/redis"
    "$USER_HOME/data/miniflux/db"
    "$USER_HOME/data/mm2us"
    "$USER_HOME/data/notify"
    "$USER_HOME/data/ntfy"
    "$USER_HOME/data/portainer"
    "$USER_HOME/data/qbittorrent"
    "$USER_HOME/data/screenshot"
    "$USER_HOME/data/stirling-pdf"
    "$USER_HOME/data/traefik/certs"
    "$USER_HOME/data/uptime-kuma"
    "$USER_HOME/data/vaultwarden"
    "$USER_HOME/data/code-server"
    "$USER_HOME/plex/downloads"
    "$USER_HOME/plex/movies"
    "$USER_HOME/plex/tv"
    "$USER_HOME/plex/music"
    "$USER_HOME/plex/audiobooks"
    "$USER_HOME/plex/podcasts"
    "$USER_HOME/.sops"
    "$USER_HOME/.docker"
)

#=============================================================================
# SETUP - Create directories
#=============================================================================
cmd_setup() {
    header "Creating directories"
    local created=0
    for dir in "${DATA_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            dim "Created: $dir"
            created=$((created + 1))
        fi
    done
    chmod 700 "$USER_HOME/.sops" 2>/dev/null || true
    chown -R 1000:1000 "$USER_HOME/plex" "$USER_HOME/data" 2>/dev/null || true
    ok "Done ($created created)"
}

#=============================================================================
# NFS - Mount/unmount NFS shares
#=============================================================================
nfs_mount() {
    local name=$1 nas_path=$2 local_path=$3
    if mountpoint -q "$local_path" 2>/dev/null; then
        dim "$name: Already mounted"
        return
    fi
    info "Mounting $name: $NAS_IP:$nas_path -> $local_path"
    mkdir -p "$local_path"
    $SUDO mount -t nfs "$NAS_IP:$nas_path" "$local_path" && ok "$name" || err "$name failed"
}

nfs_unmount() {
    local name=$1 nas_path=$2 local_path=$3
    info "Unmounting $name: $local_path"
    $SUDO umount "$local_path" 2>/dev/null && ok "$name" || dim "Not mounted"
}

nfs_status() {
    local name=$1 nas_path=$2 local_path=$3
    if mountpoint -q "$local_path" 2>/dev/null; then
        printf "${GREEN}%-10s${NC} MOUNTED   " "$name:"
        df -h "$local_path" | awk 'NR==2 {print $3"/"$2" ("$5" used)"}'
    else
        printf "${RED}%-10s${NC} NOT MOUNTED\n" "$name:"
    fi
}

cmd_nfs() {
    local action=$1 target=${2:-all}
    [ -z "$action" ] && { echo -e "Usage: $0 nfs {mount|unmount|status} [plex|backup|all]"; exit 1; }

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
# INSTALL - Deploy all services
#=============================================================================
cmd_install() {
    header "home-ops Install"

    # Prerequisites
    step "1/4" "Checking prerequisites..."
    [ ! -f "$SOPS_AGE_KEY_FILE" ] && { err "Copy age key: scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$USER_HOME/.sops/"; exit 1; }
    [ ! -d "$REPO_DIR" ] && { err "Clone repo: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"; exit 1; }

    # Install Docker
    step "2/4" "Docker..."
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | $SUDO sh
    fi
    if [ "$EUID" -ne 0 ]; then
        $SUDO usermod -aG docker "$USER"
        dim "Added $USER to docker group (re-login to take effect)"
    fi

    # Install SOPS
    if ! command -v sops &> /dev/null; then
        dim "Installing SOPS..."
        $SUDO curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
        $SUDO chmod +x /usr/local/bin/sops
    fi

    # Setup directories
    step "3/4" "Directories..."
    cmd_setup

    # Create external networks
    $SUDO docker network create traefik 2>/dev/null || true
    $SUDO docker network create media 2>/dev/null || true

    # Registry auth
    cd "$REPO_DIR"
    DH_USER=$(sops -d infra/docker-cd/.enc.env 2>/dev/null | grep "^DOCKER_HUB_USER=" | cut -d= -f2 || true)
    DH_TOKEN=$(sops -d infra/docker-cd/.enc.env 2>/dev/null | grep "^DOCKER_HUB_TOKEN=" | cut -d= -f2 || true)
    GH_TOKEN=$(sops -d infra/docker-cd/.enc.env 2>/dev/null | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2 || true)

    [ -n "$DH_TOKEN" ] && echo "$DH_TOKEN" | $SUDO docker login -u "$DH_USER" --password-stdin
    [ -n "$GH_TOKEN" ] && echo "$GH_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin

    # Copy docker config from root (created by sudo docker login) to user home
    if [ "$EUID" -ne 0 ]; then
        $SUDO mkdir -p /root/.docker
        $SUDO cp /root/.docker/config.json "$USER_HOME/.docker/config.json" 2>/dev/null || true
    fi
    chmod 600 "$USER_HOME/.docker/config.json" 2>/dev/null || true

    # Deploy core services (order matters)
    step "4/4" "Deploying..."

    deploy_compose() {
        local dir=$1 name=$2
        info "Deploying $name..."
        cd "$dir"
        if [ -f .enc.env ]; then
            local tmp=$(mktemp)
            sops -d .enc.env > "$tmp"
            $SUDO docker compose --env-file "$tmp" up -d 2>/dev/null || warn "$name not started"
            rm -f "$tmp"
        else
            $SUDO docker compose up -d 2>/dev/null || warn "$name not started"
        fi
    }

    deploy_compose "$REPO_DIR/apps/traefik" traefik
    deploy_compose "$REPO_DIR/apps/authelia" authelia
    deploy_compose "$REPO_DIR/infra/docker-cd" docker-cd

    header "Done"
    echo ""
    echo -e "${BOLD}Containers:${NC}"
    $SUDO docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
    echo ""
    ok "docker-cd will auto-deploy remaining apps within 60s: ${CYAN}https://cd.jaw.dev${NC}"
}

#=============================================================================
# UNINSTALL - Remove all services
#=============================================================================
cmd_uninstall() {
    header "home-ops Uninstall"
    echo -e "${RED}This will remove ALL containers, networks, and prune images.${NC}"
    read -p "Continue? [y/N] " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

    # Stop docker-cd first to prevent re-deployments
    step "1/4" "Stopping docker-cd..."
    cd "$REPO_DIR/infra/docker-cd" 2>/dev/null && $SUDO docker compose down -v 2>/dev/null || true

    # Stop all app compose projects
    step "2/4" "Stopping all apps..."
    for dir in "$REPO_DIR"/apps/*/; do
        if [ -f "$dir/docker-compose.yml" ]; then
            dim "Stopping $(basename "$dir")..."
            cd "$dir" && $SUDO docker compose down -v 2>/dev/null || true
        fi
    done
    cd "$USER_HOME"

    step "3/4" "Removing networks..."
    for i in 1 2 3; do
        $SUDO docker network prune -f 2>/dev/null || true
        $SUDO docker network rm traefik 2>/dev/null || true
        $SUDO docker network rm media 2>/dev/null || true
        sleep 2
    done

    step "4/4" "Pruning images..."
    $SUDO docker image prune -af 2>/dev/null || true
    $SUDO docker system prune -af 2>/dev/null || true

    header "Done"
    cmd_status
}

#=============================================================================
# STATUS - Show current status
#=============================================================================
cmd_status() {
    header "Status"
    echo ""
    echo -e "${BOLD}Containers:${NC}"
    $SUDO docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || dim "None"
    echo ""
    echo -e "${BOLD}NFS Mounts:${NC}"
    cmd_nfs status
    echo ""
    echo -e "${BOLD}Disk:${NC}"
    df -h "$USER_HOME/data" "$USER_HOME/plex" 2>/dev/null | tail -n +2 || true
}

#=============================================================================
# UPDATE-INFRA - Redeploy docker-cd (can't self-update)
#=============================================================================
cmd_update_infra() {
    header "Updating infra"
    cd "$REPO_DIR"
    info "Pulling latest..."
    git pull

    step "1/1" "Redeploying docker-cd..."
    cd "$REPO_DIR/infra/docker-cd"
    $SUDO docker compose pull 2>/dev/null || true
    local tmp=$(mktemp)
    sops -d .enc.env > "$tmp"
    $SUDO docker compose --env-file "$tmp" up -d 2>/dev/null || warn "docker-cd not started"
    rm -f "$tmp"

    header "Done"
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
    update-infra)
        cmd_update_infra
        ;;
    *)
        echo -e "${BOLD}home-ops${NC} management script"
        echo ""
        echo -e "Usage: ${CYAN}$0${NC} <command> [args]"
        echo ""
        echo -e "${BOLD}Commands:${NC}"
        echo -e "  ${GREEN}setup${NC}                    Create all data directories"
        echo -e "  ${GREEN}nfs mount${NC} [target]       Mount NFS shares (plex|backup|all)"
        echo -e "  ${GREEN}nfs unmount${NC} [target]     Unmount NFS shares"
        echo -e "  ${GREEN}nfs status${NC}               Show NFS mount status"
        echo -e "  ${GREEN}install${NC}                  Deploy all services"
        echo -e "  ${GREEN}uninstall${NC}                Remove all services and cleanup"
        echo -e "  ${GREEN}update-infra${NC}             Redeploy docker-cd"
        echo -e "  ${GREEN}status${NC}                   Show containers, mounts, disk usage"
        echo ""
        echo -e "${BOLD}Examples:${NC}"
        echo -e "  ${DIM}$0 setup${NC}                 # Create directories"
        echo -e "  ${DIM}$0 nfs mount${NC}             # Mount all NFS shares"
        echo -e "  ${DIM}$0 nfs mount plex${NC}        # Mount only plex"
        echo -e "  ${DIM}$0 install${NC}               # Deploy everything"
        echo -e "  ${DIM}$0 status${NC}                # Show status"
        exit 1
        ;;
esac
