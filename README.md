# home-ops


[![Docker Swarm](https://img.shields.io/badge/Docker-Swarm-2496ED?style=flat&logo=docker&logoColor=white)](https://docs.docker.com/engine/swarm/)
[![Traefik](https://img.shields.io/badge/Traefik-Proxy-24A1C1?style=flat&logo=traefikproxy&logoColor=white)](https://traefik.io)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?style=flat&logo=renovatebot&logoColor=white)](https://github.com/renovatebot/renovate)
[![SOPS](https://img.shields.io/badge/SOPS-encrypted-FF6F00?style=flat&logo=mozilla&logoColor=white)](https://github.com/getsops/sops)

GitOps-driven homelab running on Docker Swarm


## Overview

Push to git, [doco-cd](https://github.com/kimdre/doco-cd) deploys with zero-downtime rolling updates. Secrets encrypted with SOPS. Private apps use [doco-deploy-workflow](https://github.com/wajeht/doco-deploy-workflow) for instant deploys.

```
public:  git push → webhook → doco-cd → deploy
private: push tag → build → update home-ops → deploy
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

## Hardware

| Device | RAM | Storage | OS | Function |
|--------|-----|---------|----|---------|
| Dell OptiPlex 5050 | 32GB | 1TB SSD | Ubuntu 24.04 | Docker Swarm |
| Dell OptiPlex 7050 | 32GB | 1TB SSD | Ubuntu 22.04 | Docker Swarm |
| Synology DS423+ | - | 25TB SHR | DSM | NAS |
| UniFi Cloud Gateway Ultra | - | - | - | Router |
| TP-Link TL-SG608P | - | - | - | PoE Switch |
| Raspberry Pi 5 + PoE HAT | 8GB | 128GB SD | Raspberry Pi OS | AdGuard |
| CyberPower 1500VA AVR | - | - | - | UPS |

## Docs

- [Quick Start](docs/quick-start.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Adding Apps](docs/adding-apps.md)
- [SSL Setup](docs/ssl.md)
- [Secrets](docs/secrets.md)


## License

Distributed under the MIT License © [wajeht](https://github.com/wajeht). See [LICENSE](./LICENSE) for more information.
