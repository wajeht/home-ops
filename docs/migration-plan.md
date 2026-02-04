# Migration Plan: CapRover to home-ops

Migrate from CapRover on OptiPlex 7050 to home-ops.

## Servers

| Alias | Hostname | Model | IP | CPU | OS | Status |
|-------|----------|-------|-----|-----|-----|--------|
| `one` | three | OptiPlex 7050 | 192.168.4.161 | i7-7700 @ 4.2GHz | Ubuntu 22.04 | CapRover (source) |
| `plex` | jaw | OptiPlex 5050 | 192.168.4.162 | i7-6700 @ 4.0GHz | Ubuntu 24.04 | home-ops (target) |

### SSH Access

```bash
# From Mac
sshpass -p 'password' ssh jaw@192.168.4.161  # 7050 (CapRover)
sshpass -p 'password' ssh jaw@192.168.4.162  # 5050 (home-ops)
```

## Decision: Keep 7050

7050 has better hardware (newer CPU, better thermals). Plan:
1. Copy configs from 7050 to 5050
2. Or: wipe 7050, install Ubuntu 24.04, deploy home-ops there

---

## CapRover Inventory (7050)

### Running Containers

```
srv-captain--plex           plexinc/pms-docker:latest
srv-captain--radarr         linuxserver/radarr:6.0.4
srv-captain--prowlarr       linuxserver/prowlarr:2.3.0
srv-captain--overseerr      linuxserver/overseerr:1.33.2
srv-captain--flaresolverr   flaresolverr:v3.3.21
qbittorrent                 linuxserver/qbittorrent:4.6.7
gluetun                     qmcgaw/gluetun:v3.41.0

srv-captain--favicon        ghcr.io/wajeht/favicon
srv-captain--ufc            ghcr.io/wajeht/ufc
srv-captain--commit         ghcr.io/wajeht/commit
srv-captain--screenshot     ghcr.io/wajeht/screenshot
srv-captain--calendar       ghcr.io/wajeht/calendar
srv-captain--bang           ghcr.io/wajeht/bang
srv-captain--gains          ghcr.io/wajeht/gains
srv-captain--www            ghcr.io/wajeht/jaw.dev
srv-captain--git            ghcr.io/wajeht/git
srv-captain--ip             ghcr.io/wajeht/ip
srv-captain--notify         ghcr.io/wajeht/notify
srv-captain--close-powerlifting  ghcr.io/wajeht/close-powerlifting
srv-captain--mm2us          ghcr.io/wajeht/img-captain-mm2us

gitea                       gitea/gitea:latest
mirror-to-gitea             jaedle/mirror-to-gitea:latest
cloudflared                 cloudflare/cloudflared:latest
captain-captain             caprover/caprover:1.14.1
captain-nginx               nginx:1.27.2
captain-certbot             certbot-customized:latest
```

### Config Volumes to Migrate

| App | Size | Source Path |
|-----|------|-------------|
| Plex | 14GB | `/var/lib/docker/volumes/captain--plex-config/_data` |
| Radarr | 1.3GB | `/var/lib/docker/volumes/captain--radarr-config/_data` |
| Prowlarr | 46MB | `/var/lib/docker/volumes/captain--prowlarr-config/_data` |
| Overseerr | 1GB | `/var/lib/docker/volumes/captain--overseerr-config/_data` |
| qBittorrent | ? | `/var/lib/docker/volumes/vpn-qbt_qbittorrent_config/_data` |

**Not found:** Sonarr, Tautulli (not running on CapRover)

### CapRover Data Location

```
/captain/
├── data/
│   ├── config-captain.json    # CapRover config
│   └── letencrypt/            # SSL certs
├── generated/
└── temp/
```

---

## Migration Steps

### Option A: Copy configs to 5050 (jaw)

Keep 5050 as home-ops server, just copy media app configs.

```bash
# SSH to 7050
sshpass -p 'password' ssh jaw@192.168.4.161

# Copy configs to jaw server (run as root)
sudo rsync -avz /var/lib/docker/volumes/captain--plex-config/_data/ jaw@192.168.4.162:/home/jaw/data/media/plex/
sudo rsync -avz /var/lib/docker/volumes/captain--radarr-config/_data/ jaw@192.168.4.162:/home/jaw/data/media/radarr/
sudo rsync -avz /var/lib/docker/volumes/captain--prowlarr-config/_data/ jaw@192.168.4.162:/home/jaw/data/media/prowlarr/
sudo rsync -avz /var/lib/docker/volumes/captain--overseerr-config/_data/ jaw@192.168.4.162:/home/jaw/data/media/overseerr/
sudo rsync -avz /var/lib/docker/volumes/vpn-qbt_qbittorrent_config/_data/ jaw@192.168.4.162:/home/jaw/data/qbittorrent/
```

Then on jaw (5050):
```bash
# Fix ownership
sudo chown -R 1000:1000 ~/data/media ~/data/qbittorrent

# Deploy home-ops
./home-ops/scripts/home-ops.sh install
```

### Option B: Wipe 7050, fresh install

1. **Backup configs locally first:**
```bash
# On 7050
sudo mkdir -p /tmp/backup
sudo cp -r /var/lib/docker/volumes/captain--plex-config/_data /tmp/backup/plex
sudo cp -r /var/lib/docker/volumes/captain--radarr-config/_data /tmp/backup/radarr
sudo cp -r /var/lib/docker/volumes/captain--prowlarr-config/_data /tmp/backup/prowlarr
sudo cp -r /var/lib/docker/volumes/captain--overseerr-config/_data /tmp/backup/overseerr
sudo cp -r /var/lib/docker/volumes/vpn-qbt_qbittorrent_config/_data /tmp/backup/qbittorrent

# Copy to NAS or external storage
sudo rsync -avz /tmp/backup/ nas:/backup/caprover-migration/
```

2. **Reinstall Ubuntu 24.04** on 7050

3. **Deploy home-ops:**
```bash
# Clone repo
git clone https://github.com/wajeht/home-ops.git ~/home-ops

# Copy age key from Mac
scp ~/.sops/age-key.txt jaw@192.168.4.161:~/.sops/

# Run install
./home-ops/scripts/home-ops.sh install
```

4. **Restore configs:**
```bash
# From NAS
rsync -avz nas:/backup/caprover-migration/plex/ ~/data/media/plex/
rsync -avz nas:/backup/caprover-migration/radarr/ ~/data/media/radarr/
rsync -avz nas:/backup/caprover-migration/prowlarr/ ~/data/media/prowlarr/
rsync -avz nas:/backup/caprover-migration/overseerr/ ~/data/media/overseerr/
rsync -avz nas:/backup/caprover-migration/qbittorrent/ ~/data/qbittorrent/

# Fix ownership
sudo chown -R 1000:1000 ~/data
```

---

## Post-Migration

### Update DNS/Cloudflare

Point domains to new server IP if switching from 7050 to 5050 or vice versa.

### Verify Services

```bash
./home-ops/scripts/home-ops.sh status
```

Check each app:
- https://plex.jaw.dev
- https://radarr.jaw.dev
- https://prowlarr.jaw.dev
- https://overseerr.jaw.dev
- https://qbit.jaw.dev

### Reconfigure Connections

After migration, verify:
- Radarr → Prowlarr connection
- Radarr → qBittorrent (host: `gluetun`, port: `8085`)
- Overseerr → Plex/Radarr connections
- Plex library paths (`/movies`, `/tv`)

---

## Apps NOT in home-ops

These CapRover apps need manual migration or recreation:

| App | Image | Notes |
|-----|-------|-------|
| bang | ghcr.io/wajeht/bang | Add to home-ops? |
| gains | ghcr.io/wajeht/gains | Add to home-ops? |
| www (jaw.dev) | ghcr.io/wajeht/jaw.dev | Personal site |
| git | ghcr.io/wajeht/git | Add to home-ops? |
| ip | ghcr.io/wajeht/ip | Add to home-ops? |
| notify | ghcr.io/wajeht/notify | Add to home-ops? |
| close-powerlifting | ghcr.io/wajeht/close-powerlifting | Add to home-ops? |
| mm2us | ghcr.io/wajeht/img-captain-mm2us | Add to home-ops? |
| mirror-to-gitea | jaedle/mirror-to-gitea | Gitea mirror tool |
| cloudflared | cloudflare/cloudflared | Tunnel (using Traefik instead) |

---

## Retire Old Server

After successful migration:

```bash
# On old server
sudo docker swarm leave --force  # if swarm
sudo docker stop $(docker ps -q)
sudo docker system prune -af

# Or just power off and repurpose
sudo poweroff
```
