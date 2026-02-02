# home-ops

GitOps for Docker Compose using [doco-cd](https://github.com/kimdre/doco-cd).

## Overview

Push to git → webhook triggers doco-cd → apps deploy automatically.

```
home-ops/
├── apps/                    # auto-discovered, deployed via webhook
│   ├── homepage/
│   ├── whoami/
│   └── prometheus/
├── infrastructure/          # core services
│   ├── traefik/             # reverse proxy + TLS
│   └── doco-cd/             # gitops controller
├── secrets.enc.env          # SOPS encrypted secrets
└── docs/                    # documentation
```

## Documentation

- **[VPS Setup](docs/vps-setup.md)** - Setting up a new server from scratch
- **[Secrets Management](docs/secrets.md)** - SOPS encryption workflow
- **[Adding Apps](docs/adding-apps.md)** - Deploy new applications

## Quick Reference

### Add an app
```bash
mkdir -p apps/myapp
# Create apps/myapp/docker-compose.yml
git add -A && git commit -m "add myapp" && git push
```

### Edit secrets
```bash
sops secrets.enc.env
```

### Check logs
```bash
ssh root@VPS 'docker logs doco-cd'
```

## Stack

| Component | Purpose |
|-----------|---------|
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps deployment |
| [Traefik](https://traefik.io) | Reverse proxy + TLS |
| [SOPS](https://github.com/getsops/sops) | Secrets encryption |
| [Renovate](https://github.com/apps/renovate) | Auto-update images |

## URLs

- https://home.wajeht.com
- https://whoami.wajeht.com
- https://traefik.wajeht.com
- https://prometheus.wajeht.com
