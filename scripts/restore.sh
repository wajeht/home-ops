#!/bin/bash
# Restore app data from backup
# Usage: ./scripts/restore.sh [source]
set -eo pipefail

# Config
HOME_DIR="${HOME:-/home/jaw}"
BACKUP_SRC="${1:-$HOME_DIR/backup}"

echo "=== Restore from $BACKUP_SRC ==="
echo "WARNING: This will overwrite existing data!"
read -p "Continue? (y/N) " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

# Create directories first
echo "[1/4] Creating directories..."
mkdir -p "$HOME_DIR/.sops" "$HOME_DIR/.docker" "$HOME_DIR/data"

# Restore SOPS key (critical - do first)
echo "[2/4] Restoring ~/.sops..."
rsync -av "$BACKUP_SRC/sops/" "$HOME_DIR/.sops/"
chmod 700 "$HOME_DIR/.sops"

# Restore Docker config
echo "[3/4] Restoring ~/.docker/config.json..."
rsync -av "$BACKUP_SRC/docker-config.json" "$HOME_DIR/.docker/config.json" 2>/dev/null || true
chmod 600 "$HOME_DIR/.docker/config.json" 2>/dev/null || true

# Restore app data
echo "[4/4] Restoring ~/data..."
rsync -av "$BACKUP_SRC/data/" "$HOME_DIR/data/"
chown -R 1000:1000 "$HOME_DIR/data" 2>/dev/null || true

echo ""
echo "=== Restore complete ==="
echo "Next: Run ./scripts/install.sh to deploy services"
