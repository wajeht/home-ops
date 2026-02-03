# home-ops

GitOps-driven homelab running on Docker Swarm.

## How It Works

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│   GitHub    │      │   doco-cd   │      │   Docker    │
│             │ pull │             │deploy│   Swarm     │
│  git push   │─────▶│  GitOps     │─────▶│             │
│             │ 60s  │  Controller │      │  Services   │
└─────────────┘      └─────────────┘      └─────────────┘
                            │
                     ┌──────┴──────┐
                     │    SOPS     │
                     │  Decrypts   │
                     │  .enc.env   │
                     └─────────────┘
```

1. Push changes to GitHub
2. doco-cd polls repo every 60s
3. Detects changes, decrypts secrets via SOPS
4. Deploys with zero-downtime rolling updates

## Architecture

```
                        ┌─────────────────────────────────────┐
                        │            Cloudflare               │
                        │         DNS + SSL Certs             │
                        └──────────────────┬──────────────────┘
                                           │
                        ┌──────────────────▼──────────────────┐
                        │             Traefik                 │
                        │     Reverse Proxy + Auto TLS        │
                        │         *.wajeht.com                │
                        └──────────────────┬──────────────────┘
                                           │
          ┌────────────────────────────────┼────────────────────────────────┐
          │                                │                                │
┌─────────▼─────────┐          ┌──────────▼──────────┐          ┌──────────▼──────────┐
│      Media        │          │     Productivity    │          │    Infrastructure   │
├───────────────────┤          ├─────────────────────┤          ├─────────────────────┤
│ Plex              │          │ Vaultwarden         │          │ Traefik             │
│ Radarr / Sonarr   │          │ Gitea               │          │ doco-cd             │
│ Prowlarr          │          │ Miniflux            │          │ Uptime Kuma         │
│ Overseerr         │          │ Stirling PDF        │          │ Prometheus          │
│ Tautulli          │          │ IT-Tools            │          │ Ntfy                │
│ Navidrome         │          │ Changedetection     │          │ Homepage            │
│ Audiobookshelf    │          │ Linx                │          │                     │
│ qBittorrent+VPN   │          │                     │          │                     │
└───────────────────┘          └─────────────────────┘          └─────────────────────┘
```

## Stack

| Component | Purpose |
|-----------|---------|
| [Docker Swarm](https://docs.docker.com/engine/swarm/) | Container orchestration with rolling updates |
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps controller with SOPS integration |
| [Traefik](https://traefik.io) | Reverse proxy with automatic Let's Encrypt |
| [SOPS](https://github.com/getsops/sops) | Encrypted secrets in git |
| [Renovate](https://github.com/renovatebot/renovate) | Automated dependency updates |

## Quick Start

```bash
# Clone repo
git clone https://github.com/wajeht/home-ops.git ~/home-ops

# Copy SOPS key
scp ~/.sops/age-key.txt user@server:~/.sops/

# Install
cd ~/home-ops && ./scripts/install.sh
```

## Project Structure

```
home-ops/
├── apps/                   # Application stacks
│   ├── media/              # Plex, *arr, qBittorrent
│   ├── vaultwarden/        # Password manager
│   └── ...
├── infra/                  # Core infrastructure
│   ├── traefik/            # Reverse proxy
│   └── doco-cd/            # GitOps controller
├── scripts/
│   ├── install.sh          # Full setup
│   ├── uninstall.sh        # Clean removal
│   ├── backup.sh           # Backup to NAS
│   └── restore.sh          # Restore from backup
└── docs/                   # Documentation
```

## Data Storage

All persistent data stored in `~/data/` for easy backup:

```
~/data/
├── traefik/certs/          # SSL certificates
├── vaultwarden/            # Password vault
├── media/                  # Plex, *arr configs
├── gitea/                  # Git repositories
└── ...
```

## Documentation

- [Disaster Recovery](docs/disaster-recovery.md)
- [Adding Apps](docs/adding-apps.md)
- [SSL/TLS Setup](docs/ssl.md)
- [Secrets Management](docs/secrets.md)
