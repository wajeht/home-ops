# home-ops

GitOps-driven homelab on Docker Swarm

[![Docker Swarm](https://img.shields.io/badge/Docker-Swarm-2496ED?style=flat&logo=docker&logoColor=white)](https://docs.docker.com/engine/swarm/)
[![Traefik](https://img.shields.io/badge/Traefik-Proxy-24A1C1?style=flat&logo=traefikproxy&logoColor=white)](https://traefik.io)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?style=flat&logo=renovatebot&logoColor=white)](https://github.com/renovatebot/renovate)
[![SOPS](https://img.shields.io/badge/SOPS-encrypted-FF6F00?style=flat&logo=mozilla&logoColor=white)](https://github.com/getsops/sops)

## Overview

Push to git, [doco-cd](https://github.com/kimdre/doco-cd) deploys with zero-downtime rolling updates. Secrets encrypted with SOPS.

```
git push → webhook → doco-cd → decrypts secrets → docker stack deploy
```

## Tech Stack

| Component | Purpose |
|-----------|---------|
| [Docker Swarm](https://docs.docker.com/engine/swarm/) | Container orchestration |
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps controller |
| [Traefik](https://traefik.io) | Reverse proxy + Let's Encrypt |
| [SOPS](https://github.com/getsops/sops) | Secrets encryption |
| [Renovate](https://github.com/renovatebot/renovate) | Dependency updates |

## Repository Structure

```
home-ops/
├── apps/
│   ├── media/              # plex, radarr, sonarr, prowlarr, overseerr, tautulli
│   ├── vpn-qbit/           # qbittorrent + gluetun vpn
│   ├── audiobookshelf/     # audiobooks & podcasts
│   ├── navidrome/          # music streaming
│   ├── vaultwarden/        # password manager
│   ├── miniflux/           # rss reader
│   ├── gitea/              # git mirror
│   ├── homepage/           # dashboard
│   ├── uptime-kuma/        # monitoring
│   └── ...                 # +10 more
├── infra/
│   ├── traefik/            # reverse proxy + ssl
│   └── doco-cd/            # gitops controller
├── scripts/                # install, backup, restore
└── docs/                   # documentation
```

## Docs

- [Quick Start](docs/quick-start.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Adding Apps](docs/adding-apps.md)
- [SSL Setup](docs/ssl.md)
- [Secrets](docs/secrets.md)
