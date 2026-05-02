# home-ops

![Uptime](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/uptime&style=flat&cacheSeconds=300)
![Containers](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/containers&style=flat&cacheSeconds=300)
![CPU](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/cpu&style=flat&cacheSeconds=300)
![Load](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/load&style=flat&cacheSeconds=300)
![RAM](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/ram&style=flat&cacheSeconds=300)
![Swap](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/swap&style=flat&cacheSeconds=300)
![Disk](https://img.shields.io/endpoint?url=https://cd.jaw.dev/badges/disk&style=flat&cacheSeconds=300)
![Temp](https://img.shields.io/endpoint?url=https%3A%2F%2Fcd.jaw.dev%2Fbadges%2Ftemperature%3Funit%3Df&style=flat&cacheSeconds=300)
![Power](https://img.shields.io/endpoint?url=https://power-badge.jaw.dev&style=flat&cacheSeconds=300)

```mermaid
flowchart LR
    subgraph app_repo["GitHub — custom-repo"]
        app_push([git push])
        app_renovate([Renovate])
        ci[GitHub Actions]
        ghcr[(GHCR)]
    end

    subgraph ops_repo["GitHub — home-ops"]
        ops_push([git push])
        ops_renovate([Renovate])
        ops_ci[GitHub Actions]
    end

    app_push --> ci -->|build + push| ghcr
    app_renovate -->|update deps| ci
    ci -->|update tag| ops_ci
    ops_push --> ops_ci
    ops_renovate -->|update images| ops_ci
    ops_ci -->|/api/sync| cf --> unifi -->|:80/:443| traefik -->|proxy| apps

    subgraph cloudflare[Cloudflare]
        cf((WAF))
        cf_region([Region Blocking])
        cf_ddos([DDoS Protection])
        cf_bot([Bot Management])
    end

    subgraph infra[Infra]
        subgraph dell[Dell OptiPlex 7050 Micro]
            docker_cd[docker-cd] -->|compose up| apps
            traefik[Traefik] -->|proxy| docker_cd
            traefik -->|forward-auth| google_auth[Google Auth] -->|authed| apps

            apps["apps/*
            Home Assistant
            Plex
            Gitea
            Vaultwarden
            Paperless-ngx
            Immich
            +54 more"]
        end

        subgraph nas[Synology DS923+]
            nfs[(NFS)]
        end

        subgraph ucg[UniFi Cloud Gateway Fiber]
            unifi{{Firewall}}
            ucg_cf([Cloudflare IPs Only])
            ucg_region([Region Blocking])
            ucg_ids([IDS/IPS])
            ucg_threat([Threat Management])
        end

        subgraph pi[Raspberry Pi 5]
            adguard[AdGuard Home] --> unbound[Unbound]
        end

        subgraph slzb[SMLIGHT SLZB-MR3U]
            zigbee{{Zigbee Gateway}}
        end

        zigbee -->|Zigbee| plugs([Smart Plugs x4])
        zigbee -->|Zigbee| switches([Smart Switches x2])

        subgraph uswflex[UniFi Flex 2.5G PoE]
            poe{{PoE Switch}}
        end

        subgraph u6[UniFi U6+]
            ap{{WiFi 6 AP}}
        end

        subgraph unvr[UniFi UNVR Instant]
            nvr{{NVR}}
        end

        subgraph dell5050[Dell OptiPlex 5050 Micro]
            talos_cp{{Talos K8s Control Plane}}
        end

        subgraph dell7070[Dell OptiPlex 7070 Micro]
            talos_worker{{Talos K8s Worker}}
        end

        nfs -->|NFS| apps
        adguard -->|DNS| unifi
        unifi -->|2.5GbE| nfs
        unifi --> poe
        unifi -->|2.5GbE| dell
        unifi -->|2.5GbE| dell5050
        unifi -->|2.5GbE| dell7070
        poe -->|PoE| zigbee
        poe -->|PoE| adguard
        poe -->|PoE| ap
        poe -->|PoE| nvr
        nvr -->|WiFi| camera([G6 Instant Camera])
    end

    docker_cd -.->|poll 5m| traefik -.->|poll 5m| unifi -.->|poll 5m| cf -.->|poll 5m| ops_ci

    style app_repo fill:#e8f4fd,stroke:#4a90d9
    style ops_repo fill:#e8f4fd,stroke:#4a90d9
    style infra fill:#f0fdf4,stroke:#22c55e,stroke-width:2px
    style cloudflare fill:#fde8d0,stroke:#f6821f
    style cf fill:#fde8d0,stroke:#f6821f,color:#333
    style cf_region fill:#fde8d0,stroke:#f6821f,color:#333
    style cf_ddos fill:#fde8d0,stroke:#f6821f,color:#333
    style cf_bot fill:#fde8d0,stroke:#f6821f,color:#333
    style ucg_cf fill:#fde8e8,stroke:#dc2626,color:#333
    style ucg_region fill:#fde8e8,stroke:#dc2626,color:#333
    style ucg_ids fill:#fde8e8,stroke:#dc2626,color:#333
    style ucg_threat fill:#fde8e8,stroke:#dc2626,color:#333
    style ghcr fill:#d1d5db,stroke:#24292e,color:#333
    classDef gha fill:#d1d5db,stroke:#24292e,color:#333
    class ci,ops_ci gha
    style app_renovate fill:#d5d7f2,stroke:#1a1f6c,color:#333
    style ops_renovate fill:#d5d7f2,stroke:#1a1f6c,color:#333
    style adguard fill:#d4f0d7,stroke:#68bc71,color:#333
    style unbound fill:#d4f0d7,stroke:#68bc71,color:#333
    style unifi fill:#fde8e8,stroke:#dc2626,color:#333
    style zigbee fill:#f5e6ff,stroke:#9b59b6,color:#333
    style poe fill:#d1d5db,stroke:#6b7280,color:#333
    style ap fill:#cce0f5,stroke:#0559c9,color:#333
    style traefik fill:#e0f2fe,stroke:#0284c7,color:#333
    style docker_cd fill:#dbeafe,stroke:#2563eb,color:#333
    style google_auth fill:#fef3c7,stroke:#d97706,color:#333
    style apps fill:#f0fdf4,stroke:#16a34a,color:#333
    style nfs fill:#e0e7ff,stroke:#4f46e5,color:#333
    classDef trigger fill:#fce7f3,stroke:#db2777,color:#333
    class app_push,ops_push trigger
    style dell fill:#fffbeb,stroke:#d97706
    style dell5050 fill:#fffbeb,stroke:#d97706
    style dell7070 fill:#fffbeb,stroke:#d97706
    style talos_cp fill:#dbeafe,stroke:#326ce5,color:#333
    style talos_worker fill:#dbeafe,stroke:#326ce5,color:#333
    style nas fill:#fffbeb,stroke:#d97706
    style ucg fill:#fef2f2,stroke:#dc2626
    style pi fill:#f0fdf4,stroke:#22c55e
    style slzb fill:#faf5ff,stroke:#9b59b6
    style uswflex fill:#f3f4f6,stroke:#6b7280
    style u6 fill:#eff6ff,stroke:#0559c9
    style unvr fill:#fef2f2,stroke:#dc2626
    style nvr fill:#fde8e8,stroke:#dc2626,color:#333
    style camera fill:#fde8e8,stroke:#dc2626,color:#333
    style plugs fill:#f5e6ff,stroke:#9b59b6,color:#333
    style switches fill:#f5e6ff,stroke:#9b59b6,color:#333
    linkStyle 29 stroke:#22c55e,stroke-dasharray:5
    linkStyle 30 stroke:#22c55e,stroke-dasharray:5
    linkStyle 31 stroke:#22c55e,stroke-dasharray:5
    linkStyle 32 stroke:#22c55e,stroke-dasharray:5
```

GitOps-driven homelab running on Docker Compose.

Push to git, [docker-cd](https://github.com/wajeht/docker-cd) handles the rest — auto-discovers `apps/*/`, decrypts [SOPS](https://github.com/getsops/sops) secrets, rolling deploys. [Traefik](https://traefik.io/traefik/) routes via Docker labels with wildcard SSL. [Renovate](https://github.com/renovatebot/renovate) keeps deps fresh; own images deploy in ~1 min via [docker-cd-deploy-workflow](https://github.com/wajeht/docker-cd-deploy-workflow).

All containers [hardened](docs/adding-apps.md#container-hardening) with dropped capabilities, resource limits, and health checks. [Borgmatic](https://torsion.org/borgmatic/) backs up nightly — 8 Postgres + 24 SQLite dumps + files to NAS — with integrity checks and ntfy alerts.

## Hardware

| Device                                                                                                                                                                                                                                                                                                                                                                                                                                                    | RAM  | Storage  | OS              | Function          |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | -------- | --------------- | ----------------- |
| [Dell OptiPlex 7050 Micro (i7-7700)](https://www.amazon.com/s?k=dell+optiplex+7050+micro+i7-7700)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [WD Blue SN570 1TB NVMe](https://www.amazon.com/s?k=WD+Blue+SN570+1TB) (OS + apps)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Micron M600 1TB SATA](https://www.amazon.com/s?k=Micron+M600+1TB)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Intel I226-V 2.5GbE M.2 NIC](https://www.amazon.com/s?k=Intel+I226-V+2.5G+M.2+A%2BE+2230)                 | 32GB | 2TB      | Ubuntu 24.04    | Docker / GitOps   |
| [Dell OptiPlex 5050 Micro (i7-6700)](https://www.amazon.com/s?k=dell+optiplex+5050+micro+i7-6700)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Micron 1100 1TB SATA](https://www.amazon.com/s?k=Micron+1100+1TB) (OS)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Intel I226-V 2.5GbE M.2 NIC](https://www.amazon.com/s?k=Intel+I226-V+2.5G+M.2+A%2BE+2230)                                                                                                                            | 32GB | 1TB      | Talos v1.12.6   | K8s Control Plane |
| [Dell OptiPlex 7070 Micro (i7-9700T)](https://www.amazon.com/s?k=dell+optiplex+7070+micro+i7-9700t)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [WD Black SN730 256GB NVMe](https://www.amazon.com/s?k=WD+Black+SN730+256GB) (OS)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [SanDisk SSD 1TB SATA](https://www.amazon.com/s?k=SanDisk+SDSSDH3+1TB) (Longhorn)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Intel I226-V 2.5GbE M.2 NIC](https://www.amazon.com/s?k=Intel+I226-V+2.5G+M.2+A%2BE+2230) | 32GB | 1.25TB   | Talos v1.12.6   | K8s Worker        |
| [Raspberry Pi 5](https://www.raspberrypi.com/products/raspberry-pi-5/)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [GeeekPi P33 NVMe PoE+ HAT](https://www.amazon.com/dp/B0DMW98LBR)                                                                                                                                                                                                                                                                                     | 8GB  | 128GB SD | Raspberry Pi OS | AdGuard           |
| [Synology DS923+](https://www.amazon.com/dp/B0BM7KDN6R)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [WD Red Plus 8TB](https://www.amazon.com/s?k=WD+Red+Plus+8TB) x2<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Seagate IronWolf 12TB](https://www.amazon.com/s?k=Seagate+IronWolf+12TB) x2<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Synology E10G22-T1-Mini 10GbE NIC](https://www.amazon.com/s?k=Synology+E10G22-T1-Mini)                                                                      | 20GB | 25TB SHR | DSM             | NAS               |
| [UniFi Cloud Gateway Fiber](https://store.ui.com/us/en/products/ucg-fiber)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [Samsung 990 EVO Plus 1TB NVMe](https://www.amazon.com/s?k=Samsung+990+EVO+Plus+1TB)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [UACC SSD Tray](https://store.ui.com/us/en/category/accessories-installations/collections/drive-trays/products/uacc-ssd-tray)                                                                                                   | 3GB  | 1TB      | UniFi OS        | Firewall          |
| [UniFi U6+](https://store.ui.com/us/en/products/u6-plus)                                                                                                                                                                                                                                                                                                                                                                                                  | -    | -        | -               | WiFi 6 AP         |
| [UniFi UNVR Instant](https://store.ui.com/us/en/products/unvr-instant)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [UniFi Basic 3.5" HDD 4TB](https://store.ui.com/us/en/products/uacc-hdd-s-4tb)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [UniFi Camera G6 Instant](https://store.ui.com/us/en/products/uvc-g6-ins)                                                                                                                                                                 | 4GB  | 4TB      | UniFi OS        | NVR / Camera      |
| [SMLIGHT SLZB-MR3U](https://www.amazon.com/dp/B0FB97W6CN)<br>&nbsp;&nbsp;&nbsp;&nbsp;— [THIRDREALITY Smart Plug Gen3](https://www.amazon.com/dp/B0GHQT8TQ8) x4<br>&nbsp;&nbsp;&nbsp;&nbsp;— [THIRDREALITY Smart Switch](https://www.amazon.com/dp/B0CR9ZSV5L) x2                                                                                                                                                                                          | -    | -        | -               | Zigbee Gateway    |
| [UniFi Flex 2.5G PoE 8-Port](https://store.ui.com/us/en/products/usw-flex-2-5g-8-poe)                                                                                                                                                                                                                                                                                                                                                                     | -    | -        | -               | PoE Switch        |
| [ElecVoztile 10" Rack PDU](https://www.amazon.com/dp/B0FF41T167)                                                                                                                                                                                                                                                                                                                                                                                          | -    | -        | -               | PDU               |
| [CyberPower 1500VA AVR](https://www.amazon.com/CyberPower-CP1500AVRLCD-Intelligent-Outlets-Mini-Tower/dp/B000FBK3QK)                                                                                                                                                                                                                                                                                                                                      | -    | -        | -               | UPS               |
| [DeskPi RackMate T2 12U](https://www.amazon.com/dp/B0FYNM62F7)                                                                                                                                                                                                                                                                                                                                                                                            | -    | -        | -               | Rack              |

With all equipment connected: ~120W idle @ 120V, ~80 min UPS runtime, 87 kWh/mo (~$10/mo).

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
