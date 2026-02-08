# VPN + qBittorrent

VPN-tunneled qBittorrent using gluetun.

## Requirements

Uses Docker features:
- `devices: /dev/net/tun`
- `network_mode: service:*`
- `cap_add: NET_ADMIN`

These are required for VPN traffic routing.

## Deployment

docker-cd auto-deploys this stack with `rolling: false` (can't scale due to `container_name`).

## Traffic Flow

```
qBittorrent → network_mode:service:gluetun → VPN tunnel → Internet
     ↓
/home/jaw/plex/downloads
     ↓
Radarr/Sonarr pick up completed downloads
```

All qBittorrent traffic routes through VPN. If VPN drops, qBittorrent loses connectivity (kill switch).

## Verify VPN

```bash
docker exec gluetun wget -qO- ifconfig.me
# Should show VPN server IP, not your real IP
```
