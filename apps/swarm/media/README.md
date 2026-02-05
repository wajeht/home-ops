# Media Stack

*arr apps for media management. Plex is in separate `plex` stack (docker-compose for hardware transcoding).

## VPN Setup (AirVPN)

Before deploying, create `.enc.env` with your AirVPN credentials:

### Option A: OpenVPN (easier)

1. Go to AirVPN → Client Area → Config Generator
2. Select Linux, OpenVPN 2.6+, generate config
3. Get username/password from the config file
4. Create env file:

```bash
cat > .env << 'EOF'
VPN_SERVICE_PROVIDER=airvpn
VPN_TYPE=openvpn
OPENVPN_USER=your_username
OPENVPN_PASSWORD=your_password
SERVER_COUNTRIES=Netherlands
EOF
sops -e .env > .enc.env && rm .env
```

### Option B: WireGuard (faster)

1. Go to AirVPN → Client Area → Devices → Manage
2. Generate WireGuard keys
3. Create env file:

```bash
cat > .env << 'EOF'
VPN_SERVICE_PROVIDER=airvpn
VPN_TYPE=wireguard
WIREGUARD_PRIVATE_KEY=your_private_key
WIREGUARD_PRESHARED_KEY=your_preshared_key
WIREGUARD_ADDRESSES=your_assigned_ip
SERVER_COUNTRIES=Netherlands
EOF
sops -e .env > .enc.env && rm .env
```

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Radarr | https://radarr.jaw.dev | Movie management |
| Sonarr | https://sonarr.jaw.dev | TV show management |
| Prowlarr | https://prowlarr.jaw.dev | Indexer manager |
| Tautulli | https://tautulli.jaw.dev | Plex stats |
| Overseerr | https://overseerr.jaw.dev | Media requests |
| FlareSolverr | internal | Cloudflare bypass |

**Related stacks:**
- `apps/compose/plex/` - Plex media server (docker-compose for Intel Quick Sync)
- `apps/compose/vpn-qbit/` - qBittorrent + VPN (docker-compose)

## Traffic Flow

```
Prowlarr (indexers) → Radarr/Sonarr → qBittorrent → Gluetun VPN → Internet
                                            ↓
                                        downloads/
                                            ↓
                                          Plex
```

## Setup

1. Configure `.enc.env` with your VPN credentials
2. Deploy stack
3. Configure Prowlarr with indexers + FlareSolverr
4. Connect Radarr/Sonarr to Prowlarr and qBittorrent
5. Point Plex to /movies and /tv directories

## Prowlarr → FlareSolverr

In Prowlarr: Settings → Indexers → Add FlareSolverr:
- Host: `http://flaresolverr:8191`

## Radarr/Sonarr → qBittorrent

In Radarr/Sonarr: Settings → Download Clients → Add qBittorrent:
- Host: `gluetun` (qBittorrent uses Gluetun's network)
- Port: `8085`

See `apps/compose/vpn-qbit/README.md` for VPN setup.
