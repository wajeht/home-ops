# Plex Media Server

Plex with Intel Quick Sync hardware transcoding.

## Why docker-compose?

Docker Swarm doesn't support `devices:` directive. Plex needs `/dev/dri` access for Intel Quick Sync hardware transcoding, so it runs via `docker compose` instead of Swarm.

## Hardware Transcoding

Intel Quick Sync is enabled by passing `/dev/dri` to the container:

```yaml
devices:
  - /dev/dri:/dev/dri
```

Requires:
- Intel CPU with integrated graphics (Sandy Bridge or newer)
- Plex Pass subscription

## Verify Hardware Transcoding

Check device access:
```bash
docker exec plex ls -la /dev/dri
```

Should show:
```
card0       - GPU device
renderD128  - Render device (used for transcoding)
```

## Enable in Plex

1. Go to Settings → Transcoder
2. Enable "Use hardware acceleration when available"
3. Optionally enable "Use hardware-accelerated video encoding"

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Plex | https://plex.jaw.dev | Media server |

## First-Time Setup

Get a claim token from https://plex.tv/claim and add to environment:
```yaml
environment:
  - PLEX_CLAIM=claim-xxxx
```

## Volumes

| Path | Purpose |
|------|---------|
| `/config` | Plex database and settings |
| `/movies` | Movie library |
| `/tv` | TV show library |
| `/music` | Music library |

## Management

```bash
# Start
cd ~/home-ops/apps/plex && sudo docker compose up -d

# Stop
cd ~/home-ops/apps/plex && sudo docker compose down

# Logs
sudo docker logs plex -f

# Restart
sudo docker restart plex
```
