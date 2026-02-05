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

### 1. Fresh Server Setup

```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Init Swarm
docker swarm init
```

### 2. Restore Critical Files

```bash
# Restore from backup
rsync -av backup:~/data/ ~/data/
rsync -av backup:~/.sops/ ~/.sops/

# Create directories
mkdir -p ~/.docker ~/data
```

### 3. Setup Docker Auth (ghcr.io)

```bash
echo 'YOUR_GH_TOKEN' | docker login ghcr.io -u USERNAME --password-stdin
```

### 4. Create Docker Secrets

```bash
# Decrypt and create secrets
export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt

# Cloudflare token
sops -d apps/swarm/traefik/.enc.env | grep CF_DNS_API_TOKEN | cut -d= -f2 | \
  docker secret create cf_dns_api_token -

# GitHub token
sops -d apps/swarm/doco-cd/.enc.env | grep GH_TOKEN | cut -d= -f2 | \
  docker secret create gh_token -

# Webhook secret
sops -d apps/swarm/doco-cd/.enc.env | grep WEBHOOK_SECRET | cut -d= -f2 | \
  docker secret create webhook_secret -
```

### 5. Create Traefik Network

```bash
docker network create --driver overlay --attachable traefik
```

### 6. Deploy Infrastructure

```bash
# Traefik first
docker stack deploy -c apps/swarm/traefik/docker-compose.yml traefik

# Wait for traefik to be healthy
docker service ls

# doco-cd
docker stack deploy -c apps/swarm/doco-cd/docker-compose.yml doco-cd
```

### 7. Deploy Apps

doco-cd will auto-deploy apps from git, or manually:

```bash
for app in apps/swarm/*/; do
  name=$(basename $app)
  docker stack deploy -c ${app}docker-compose.yml $name
done
```

### 8. Mount NFS (for media)

```bash
# Add to /etc/fstab
NAS_IP:/volume1/plex /home/jaw/plex nfs defaults 0 0

# Mount
sudo mount -a
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

## Data Directory Structure

```
~/data/
├── audiobookshelf/
│   ├── config/
│   └── metadata/
├── changedetection/
├── doco-cd/
├── favicon/
├── gitea/
├── gluetun/
├── linx/
│   ├── files/
│   └── meta/
├── media/
│   ├── plex/
│   ├── prowlarr/
│   ├── radarr/
│   ├── sonarr/
│   ├── tautulli/
│   └── overseerr/
├── miniflux/
├── ntfy/
├── qbittorrent/
├── screenshot/
├── stirling-pdf/
├── traefik/
│   └── certs/
├── uptime-kuma/
└── vaultwarden/
```

## Testing Recovery

Periodically test by:
1. Spin up a test VM
2. Follow recovery steps
3. Verify services come up with data intact
