#!/bin/bash
# Backup app data and configs to NAS
# Usage: ./scripts/backup.sh [destination]
set -eo pipefail

# Config
HOME_DIR="${HOME:-/home/jaw}"
BACKUP_DEST="${1:-$HOME_DIR/backup}"
DATE=$(date +%Y-%m-%d)
LOG_FILE="/var/log/homelab-backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

mkdir -p "$BACKUP_DEST"
log "Starting backup to $BACKUP_DEST"

# App data (critical)
log "Backing up ~/data..."
rsync -av --delete "$HOME_DIR/data/" "$BACKUP_DEST/data/"

# SOPS key (critical)
log "Backing up ~/.sops..."
rsync -av "$HOME_DIR/.sops/" "$BACKUP_DEST/sops/"

# Docker config
log "Backing up ~/.docker/config.json..."
rsync -av "$HOME_DIR/.docker/config.json" "$BACKUP_DEST/docker-config.json" 2>/dev/null || true

log "Backup complete: $DATE"
log "---"

# Show sizes
echo ""
echo "Backup sizes:"
du -sh "$HOME_DIR/data" "$HOME_DIR/.sops" 2>/dev/null || true
