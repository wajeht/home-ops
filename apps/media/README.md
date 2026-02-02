# Media Stack

Plex + *arr apps with qBittorrent through Gluetun VPN.

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

### Plex Claim Token (optional)

Add to .env before encrypting:
```
PLEX_CLAIM=claim-xxxx
```
Get token from: https://plex.tv/claim

## Services

| Service | URL | Purpose |
|---------|-----|---------|
| Plex | https://plex.wajeht.com | Media server |
| Radarr | https://radarr.wajeht.com | Movie management |
| Prowlarr | https://prowlarr.wajeht.com | Indexer manager |
| qBittorrent | https://qbit.wajeht.com | Torrent client (via VPN) |
| FlareSolverr | internal | Cloudflare bypass |
| Gluetun | internal | VPN container |

## Traffic Flow

```
Prowlarr (indexers) → Radarr (movies) → qBittorrent → Gluetun VPN → Internet
                                              ↓
                                          downloads/
                                              ↓
                                            Plex
```

## Setup

1. Configure `.enc.env` with your VPN credentials
2. Deploy stack
3. Configure Prowlarr with indexers + FlareSolverr
4. Connect Radarr to Prowlarr and qBittorrent
5. Point Plex to /movies and /tv directories

## Prowlarr → FlareSolverr

In Prowlarr: Settings → Indexers → Add FlareSolverr:
- Host: `http://flaresolverr:8191`

## Radarr → qBittorrent

In Radarr: Settings → Download Clients → Add qBittorrent:
- Host: `gluetun` (not qbittorrent!)
- Port: `8085`

## Adding Sonarr (TV Shows)

Add to docker-compose.yml if needed - same pattern as Radarr.
