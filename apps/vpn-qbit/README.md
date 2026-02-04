# VPN + qBittorrent

**Deployed via doco-cd as docker-compose** (not Swarm) - uses `devices` and `network_mode` not supported in Swarm.

## Why docker-compose?

Docker Swarm doesn't support:
- `devices: /dev/net/tun`
- `network_mode: service:*`
- `cap_add: NET_ADMIN`

These are required for VPN traffic routing.

## Deployment

doco-cd auto-deploys this stack:
- Detects no `deploy:` section → uses docker-compose instead of swarm
- Auto-decrypts `.enc.env` via SOPS before deployment

## Traffic Flow

```
qBittorrent → network_mode:service:gluetun → VPN tunnel → Internet
     ↓
/home/jaw/plex/downloads
     ↓
Radarr/Sonarr (in Swarm) pick up completed downloads
```

All qBittorrent traffic routes through VPN. If VPN drops, qBittorrent loses connectivity (kill switch).

## Verify VPN

```bash
docker exec gluetun wget -qO- ifconfig.me
# Should show VPN server IP, not your real IP
```
