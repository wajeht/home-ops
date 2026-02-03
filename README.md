# home-ops


[![Docker Swarm](https://img.shields.io/badge/Docker-Swarm-2496ED?style=flat&logo=docker&logoColor=white)](https://docs.docker.com/engine/swarm/)
[![Traefik](https://img.shields.io/badge/Traefik-Proxy-24A1C1?style=flat&logo=traefikproxy&logoColor=white)](https://traefik.io)
[![Renovate](https://img.shields.io/badge/Renovate-enabled-1A1F6C?style=flat&logo=renovatebot&logoColor=white)](https://github.com/renovatebot/renovate)
[![SOPS](https://img.shields.io/badge/SOPS-encrypted-FF6F00?style=flat&logo=mozilla&logoColor=white)](https://github.com/getsops/sops)

GitOps-driven homelab running on Docker Swarm


## Overview

Push to git, [doco-cd](https://github.com/kimdre/doco-cd) picks it up via webhook and deploys to [Docker Swarm](https://docs.docker.com/engine/swarm/) with zero-downtime rolling updates. [Traefik](https://traefik.io) routes traffic with auto SSL via Cloudflare. Secrets stay encrypted with [SOPS](https://github.com/getsops/sops). [Renovate](https://github.com/renovatebot/renovate) keeps dependencies updated. Private apps use [doco-deploy-workflow](https://github.com/wajeht/doco-deploy-workflow) to build and deploy on tag push.


## Hardware

| Device | RAM | Storage | OS | Function |
|--------|-----|---------|----|---------|
| [Dell OptiPlex 5050 Micro](https://www.amazon.com/s?k=dell+optiplex+5050+micro) | 32GB | 1TB SSD | Ubuntu 24.04 | Docker Swarm |
| [Dell OptiPlex 7050 Micro](https://www.amazon.com/s?k=dell+optiplex+7050+micro) | 32GB | 1TB SSD | Ubuntu 22.04 | Docker Swarm |
| [Raspberry Pi 5 + PoE HAT](https://www.raspberrypi.com/products/raspberry-pi-5/) | 8GB | 128GB SD | Raspberry Pi OS | AdGuard |
| [Synology DS923+](https://www.amazon.com/dp/B0BM7KDN6R) | 4GB | 25TB SHR | DSM | NAS |
| [WD Red Plus 8TB](https://www.amazon.com/s?k=WD+Red+Plus+8TB) x2 | - | - | - | NAS Drives |
| [Seagate IronWolf 12TB](https://www.amazon.com/s?k=Seagate+IronWolf+12TB) x2 | - | - | - | NAS Drives |
| [UniFi Cloud Gateway Ultra](https://store.ui.com/us/en/products/ucg-ultra) | 3GB | 16GB | UniFi OS | Firewall |
| [UniFi U6+](https://store.ui.com/us/en/products/u6-plus) | - | - | - | WiFi 6 AP |
| [TP-Link TL-SG608P](https://www.amazon.com/s?k=TP-Link+TL-SG608P) | - | - | - | PoE Switch |
| [CyberPower 1500VA AVR](https://www.amazon.com/CyberPower-CP1500AVRLCD-Intelligent-Outlets-Mini-Tower/dp/B000FBK3QK) | - | - | - | UPS |

Idle: ~82W | UPS Runtime: ~2 hrs | Monthly: ~60 kWh (~$7)

## Docs

- [Quick Start](docs/quick-start.md)
- [Disaster Recovery](docs/disaster-recovery.md)
- [Adding Apps](docs/adding-apps.md)
- [SSL Setup](docs/ssl.md)
- [Secrets](docs/secrets.md)


## License

Distributed under the MIT License © [wajeht](https://github.com/wajeht). See [LICENSE](./LICENSE) for more information.
