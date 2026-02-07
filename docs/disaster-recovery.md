# Disaster Recovery

How to recreate the homelab from scratch.

## What's Backed Up Where

| Data | Location | Backup Strategy |
|------|----------|-----------------|
| App configs/databases | `~/data/` | rsync to NAS |
| SOPS age key | `~/.sops/age-key.txt` | Copy to secure location |
| Docker auth | `~/.docker/config.json` | Recreatable via `docker login` |
| Docker secrets | Swarm secrets | Recreate from .enc.env files |
| Media files | `~/plex/` (NFS) | NAS handles redundancy |
| Compose files | Git repo | Already backed up |

## Critical Files

```bash
# These MUST be backed up - can't recreate without them
~/.sops/age-key.txt      # Decrypts all .enc.env secrets
~/data/                  # All app configs and databases
```

## Recovery Steps

### 1. Restore Critical Files

```bash
rsync -av backup:~/data/ ~/data/
rsync -av backup:~/.sops/ ~/.sops/
```

### 2. Run Install

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
cd ~/home-ops && ./scripts/home-ops.sh install
```

The install script handles everything: Docker, Swarm, SOPS, secrets, networks, and all deployments.

### 3. Mount NFS (for media)

```bash
./scripts/home-ops.sh nfs mount
```

### 4. Verify

```bash
./scripts/home-ops.sh status
```

## Backup Script

```bash
#!/bin/bash
# ~/backup.sh

BACKUP_DEST="$HOME/backup"
DATE=$(date +%Y-%m-%d)

# Backup app data
rsync -av --delete ~/data/ $BACKUP_DEST/data/

# Backup critical configs
rsync -av ~/.sops/ $BACKUP_DEST/sops/
rsync -av ~/.docker/config.json $BACKUP_DEST/docker-config.json

echo "Backup complete: $DATE"
```

Add to cron:
```bash
0 3 * * * /home/jaw/backup.sh >> /var/log/backup.log 2>&1
```

## Testing Recovery

Periodically test by:
1. Spin up a test VM
2. Follow recovery steps
3. Verify services come up with data intact
