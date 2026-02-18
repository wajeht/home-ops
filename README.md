# home-ops

![Uptime](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/uptime&style=flat&cacheSeconds=300)
![Containers](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/containers&style=flat&cacheSeconds=300)
![CPU](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/cpu&style=flat&cacheSeconds=300)
![Load](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/load&style=flat&cacheSeconds=300)
![RAM](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/ram&style=flat&cacheSeconds=300)
![Swap](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/swap&style=flat&cacheSeconds=300)
![Disk](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/disk&style=flat&cacheSeconds=300)
![Temp](https://img.shields.io/endpoint?url=https%3A%2F%2Fcd.jaw.dev%2Fbadges%2Ftemperature%3Funit%3Df&style=flat&cacheSeconds=300)

GitOps-driven homelab running on Docker Compose

## Overview

```mermaid
flowchart LR
    subgraph triggers[Triggers]
        app_push([App: git push])
        ops_push([home-ops: git push])
        renovate([Renovate])
    end

    app_push --> ci([GitHub Actions]) -->|build + push| ghcr[(GHCR)]
    ghcr -->|push image| github((GitHub))
    ci -->|update tag| github
    ops_push --> ci
    renovate -->|auto-merge| ci
    github -->|poll + webhook| cf((Cloudflare)) -->|Cloudflare IPs only| unifi -->|:80/:443| caddy -->|proxy| docker_cd

    subgraph infra[Infra]
        subgraph dell[Dell OptiPlex 7050 Micro]
            docker_cd[docker-cd] -->|compose up| apps{{apps/*}}
            caddy[Caddy] -->|proxy| apps
        end

        subgraph nas[Synology DS923+]
            nfs[(NFS)]
        end

        subgraph ucg[UniFi Cloud Gateway Ultra]
            unifi{{Firewall}}
        end

        subgraph pi[Raspberry Pi 5]
            adguard[AdGuard Home]
        end

        nfs -->|NFS| apps
        adguard -->|DNS| unifi
    end

    caddy -.->|DNS01| cf

    style triggers fill:#e8f4fd,stroke:#4a90d9
    style infra fill:#f0fdf4,stroke:#22c55e,stroke-width:2px
    style cf fill:#f6821f,stroke:#f6821f,color:#fff
```

Push to git, [docker-cd](https://github.com/wajeht/docker-cd) auto-deploys. Polls every 5 min or instantly via `/api/sync` webhook. Auto-discovers all stacks in `apps/`, decrypts [SOPS](https://github.com/getsops/sops) secrets, and deploys with rolling updates. [Caddy](https://github.com/wajeht/docker-cd-caddy) routes via Docker labels with auto SSL via Cloudflare DNS challenge. [Renovate](https://github.com/renovatebot/renovate) keeps third-party deps updated (~15min: Renovate scan + docker-cd poll). Own images use [docker-cd-deploy-workflow](https://github.com/wajeht/docker-cd-deploy-workflow) which triggers `/api/sync` for instant deploy (~1min).

## Hardware

| Device                                                                                                                                                                                                                                                          | RAM  | Storage  | OS              | Function    |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------- | --------------- | ----------- |
| [Dell OptiPlex 7050 Micro (i7-7700)](https://www.amazon.com/s?k=dell+optiplex+7050+micro+i7-7700)                                                                                                                                                               | 32GB | 1TB SSD  | Ubuntu 24.04    | Docker Host |
| [Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/) + [GeeekPi P33 NVMe PoE+ HAT](https://www.amazon.com/dp/B0DMW98LBR)                                                                                                                      | 8GB  | 128GB SD | Raspberry Pi OS | AdGuard     |
| [Synology DS923+](https://www.amazon.com/dp/B0BM7KDN6R)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [WD Red Plus 8TB](https://www.amazon.com/s?k=WD+Red+Plus+8TB) x2<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Seagate IronWolf 12TB](https://www.amazon.com/s?k=Seagate+IronWolf+12TB) x2 | 4GB  | 25TB SHR | DSM             | NAS         |
| [UniFi Cloud Gateway Ultra](https://store.ui.com/us/en/products/ucg-ultra)                                                                                                                                                                                      | 3GB  | 16GB     | UniFi OS        | Firewall    |
| [UniFi U6+](https://store.ui.com/us/en/products/u6-plus)                                                                                                                                                                                                        | -    | -        | -               | WiFi 6 AP   |
| [TP-Link TL-SG608P](https://www.amazon.com/s?k=TP-Link+TL-SG608P)                                                                                                                                                                                               | -    | -        | -               | PoE Switch  |
| [CyberPower 1500VA AVR](https://www.amazon.com/CyberPower-CP1500AVRLCD-Intelligent-Outlets-Mini-Tower/dp/B000FBK3QK)                                                                                                                                            | -    | -        | -               | UPS         |

With all equipment connected: 69W idle @ 120V, 145 min UPS runtime, 50 kWh/mo (~$6/mo).

## Docs

- [Quick Start](docs/quick-start.md)
- [Adding Apps](docs/adding-apps.md)
- [Secrets](docs/secrets.md)
- [SSL Setup](docs/ssl.md)
- [Renovate](docs/renovate.md)
- [Instant Deploy](docs/instant-deploy.md)
- [Disaster Recovery](docs/disaster-recovery.md)

## License

Distributed under the MIT License © [wajeht](https://github.com/wajeht). See [LICENSE](./LICENSE) for more information.
