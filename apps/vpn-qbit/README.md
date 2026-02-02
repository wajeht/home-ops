# VPN + qBittorrent

**Runs with docker-compose, NOT Swarm** - Swarm doesn't support `devices` or `network_mode` required for VPN.

## Why Separate?

Docker Swarm limitations:
- No `devices: /dev/net/tun` support
- No `network_mode: service:*` support
- No `privileged: true` support

These are required for 100% VPN traffic routing.

## Setup

1. Copy VPN credentials from media stack:
```bash
cp ../media/.enc.env .enc.env
```

2. Deploy with docker-compose (NOT stack deploy):
```bash
docker compose up -d
```

## Traffic Flow

```
qBittorrent → network_mode:service:gluetun → VPN tunnel → Internet
     ↓
/home/jaw/plex/downloads
     ↓
Radarr/Sonarr (in Swarm) pick up completed downloads
```

All qBittorrent traffic (peers, trackers, DNS) routes through VPN.
If VPN drops, qBittorrent loses connectivity (kill switch).

## Verify VPN

```bash
# Check your public IP through VPN
docker exec gluetun wget -qO- ifconfig.me

# Should show VPN server IP, not your real IP
```
