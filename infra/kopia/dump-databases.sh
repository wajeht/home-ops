#!/bin/bash
# Pre-backup script: Dump SQLite databases for consistent backups
# Run this before Kopia snapshot via cron or Kopia actions

DUMP_DIR="/home/jaw/data/kopia/dumps"
mkdir -p "$DUMP_DIR"

echo "[$(date)] Starting database dumps..."

# Authelia
if [ -f "/home/jaw/data/authelia/db.sqlite3" ]; then
    sqlite3 /home/jaw/data/authelia/db.sqlite3 "VACUUM INTO '$DUMP_DIR/authelia.db'"
    echo "  - Authelia dumped"
fi

# Vaultwarden
if [ -f "/home/jaw/data/vaultwarden/db.sqlite3" ]; then
    sqlite3 /home/jaw/data/vaultwarden/db.sqlite3 "VACUUM INTO '$DUMP_DIR/vaultwarden.db'"
    echo "  - Vaultwarden dumped"
fi

# Changedetection
if [ -f "/home/jaw/data/changedetection/url-watches.json" ]; then
    cp /home/jaw/data/changedetection/url-watches.json "$DUMP_DIR/"
    echo "  - Changedetection copied"
fi

echo "[$(date)] Database dumps complete"
