# home-ops


[![Docker Swarm](https://img.shields.io/badge/Docker-Swarm-2496ED?style=flat&logo=docker&logoColor=white)](https://docs.docker.com/engine/swarm/)
[![Traefik](https://img.shields.io/badge/Traefik-Proxy-24A1C1?style=flat&logo=traefikproxy&logoColor=white)](https://traefik.io)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?style=flat&logo=renovatebot&logoColor=white)](https://github.com/renovatebot/renovate)
[![SOPS](https://img.shields.io/badge/SOPS-encrypted-FF6F00?style=flat&logo=mozilla&logoColor=white)](https://github.com/getsops/sops)

GitOps-driven homelab running on Docker Swarm


## Overview

```mermaid
flowchart LR
    subgraph Internet
        User([User])
        GitHub[(GitHub)]
        Cloudflare[Cloudflare DNS]
    end

    subgraph Homelab
        Traefik[Traefik]
        DocoCd[doco-cd]
        Swarm[Docker Swarm]
        Apps[Apps]
    end

    User -->|HTTPS| Cloudflare
    Cloudflare -->|SSL| Traefik
    Traefik -->|Route| Apps
    GitHub -->|Webhook| DocoCd
    DocoCd -->|Deploy| Swarm
    Swarm -->|Run| Apps
```

[Docker Swarm](https://docs.docker.com/engine/swarm/) orchestrates containers across nodes. [Traefik](https://traefik.io) handles reverse proxy with automatic Let's Encrypt SSL via Cloudflare DNS. [doco-cd](https://github.com/kimdre/doco-cd) watches this repo and deploys on webhook with zero-downtime rolling updates. Secrets encrypted with [SOPS](https://github.com/getsops/sops). [Renovate](https://github.com/renovatebot/renovate) auto-updates dependencies.

**Deploy Flow:**
```
public:  git push → webhook → doco-cd → deploy
private: push tag → build → update home-ops → deploy
```

Private apps use [doco-deploy-workflow](https://github.com/wajeht/doco-deploy-workflow) for instant deploys.


## Hardware

| Device | RAM | Storage | OS | Function |
|--------|-----|---------|----|---------|
| Dell OptiPlex 5050 | 32GB | 1TB SSD | Ubuntu 24.04 | Docker Swarm |
| Dell OptiPlex 7050 | 32GB | 1TB SSD | Ubuntu 22.04 | Docker Swarm |
| Raspberry Pi 5 + PoE HAT | 8GB | 128GB SD | Raspberry Pi OS | AdGuard |
| Synology DS423+ | 4GB | 25TB SHR | DSM | NAS |
| UniFi Cloud Gateway Ultra | 3GB | 16GB | UniFi OS | Router |
| UniFi U6+ | - | - | - | WiFi 6 AP |
| TP-Link TL-SG608P | - | - | - | PoE Switch |
| CyberPower 1500VA AVR | - | - | - | UPS |

## Docs

- [Quick Start](docs/quick-start.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Adding Apps](docs/adding-apps.md)
- [SSL Setup](docs/ssl.md)
- [Secrets](docs/secrets.md)


## License

Distributed under the MIT License © [wajeht](https://github.com/wajeht). See [LICENSE](./LICENSE) for more information.
