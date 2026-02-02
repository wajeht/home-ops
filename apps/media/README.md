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
| Sonarr | https://sonarr.wajeht.com | TV show management |
| Prowlarr | https://prowlarr.wajeht.com | Indexer manager |
| qBittorrent | https://qbit.wajeht.com | Torrent client (via VPN proxy) |
| Tautulli | https://tautulli.wajeht.com | Plex stats |
| Overseerr | https://requests.wajeht.com | Media requests |
| FlareSolverr | internal | Cloudflare bypass |
| Gluetun | internal | VPN proxy server |

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

## Radarr/Sonarr → qBittorrent

In Radarr/Sonarr: Settings → Download Clients → Add qBittorrent:
- Host: `qbittorrent`
- Port: `8085`

## qBittorrent VPN Setup (CRITICAL - DO THIS FIRST)

Docker Swarm doesn't support `network_mode: service:gluetun`, so we use Gluetun's HTTP proxy instead. **All torrent traffic routes through VPN** when configured properly.

### Step 1: Proxy Settings
1. Open https://qbit.wajeht.com (default: admin/adminadmin)
2. Go to **Settings → Connection → Proxy Server**
3. Configure:
   - Type: `HTTP`
   - Host: `gluetun`
   - Port: `8888`
   - ✅ Use proxy for peer connections
   - ✅ Use proxy for hostname lookup

### Step 2: Disable IP Leaking Features
Go to **Settings → BitTorrent**:
   - ❌ Uncheck "Enable DHT"
   - ❌ Uncheck "Enable PeX"
   - ❌ Uncheck "Enable LSD"

These features can leak your real IP to other peers.

### Step 3: Verify VPN is Working
1. Add any torrent and start downloading
2. Check https://ipleak.net in the qBittorrent browser (if available)
3. Or check Gluetun logs: `docker service logs media_gluetun`

Your public IP should show the VPN server, not your real IP.

### Why This Works
- All peer connections → HTTP proxy → Gluetun VPN → Internet
- All tracker connections → HTTP proxy → Gluetun VPN → Internet
- DNS lookups → HTTP proxy → Gluetun VPN → Internet
- ISP only sees encrypted VPN tunnel traffic
