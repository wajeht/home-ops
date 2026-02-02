# home-ops

GitOps for Docker Swarm using [doco-cd](https://github.com/kimdre/doco-cd).

## Overview

Push to git → webhook triggers doco-cd → rolling updates with zero downtime.

```
home-ops/
├── apps/                    # auto-discovered, deployed via webhook
│   ├── homepage/
│   ├── whoami/
│   └── prometheus/
├── infrastructure/          # core services (stacks)
│   ├── traefik/             # reverse proxy + TLS
│   └── doco-cd/             # gitops controller
├── secrets.enc.env          # SOPS encrypted secrets
└── docs/                    # documentation
```

## Architecture

- **Docker Swarm** - single-node swarm for rolling updates
- **doco-cd** - auto-detects Swarm, uses `docker stack deploy`
- **Traefik** - reverse proxy with swarmMode enabled
- **Docker Secrets** - encrypted secrets in Swarm Raft

## Documentation

- **[VPS Setup](docs/vps-setup.md)** - Setting up a new server from scratch
- **[Secrets Management](docs/secrets.md)** - SOPS + Docker secrets workflow
- **[Adding Apps](docs/adding-apps.md)** - Deploy new applications

## Quick Reference

### Add an app
```bash
mkdir -p apps/myapp
# Create apps/myapp/docker-compose.yml with deploy: section
git add -A && git commit -m "add myapp" && git push
```

### Edit secrets
```bash
sops secrets.enc.env
git push
ssh root@VPS 'cd ~/home-ops && ./scripts/sync-secrets.sh'
```

### Check services
```bash
ssh root@VPS 'docker service ls'
```

### View logs
```bash
ssh root@VPS 'docker service logs -f traefik_traefik'
```

### Force update
```bash
ssh root@VPS 'docker service update --force traefik_traefik'
```

## Stack

| Component | Purpose |
|-----------|---------|
| [Docker Swarm](https://docs.docker.com/engine/swarm/) | Orchestration + rolling updates |
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps deployment |
| [Traefik](https://traefik.io) | Reverse proxy + TLS |
| [SOPS](https://github.com/getsops/sops) | Secrets encryption |
| [Renovate](https://github.com/apps/renovate) | Auto-update images |

## URLs

- https://home.wajeht.com
- https://whoami.wajeht.com
- https://traefik.wajeht.com
- https://prometheus.wajeht.com
