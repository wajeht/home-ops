# home-ops

GitOps for Docker Swarm with zero-downtime rolling updates.

## Overview

Push to git → doco-cd deploys → rolling update with no downtime.

```
home-ops/
├── apps/                    # applications
│   ├── homepage/            # dashboard
│   ├── whoami/              # test service
│   └── commit/              # AI commit messages (private ghcr)
├── infrastructure/          # core services
│   ├── traefik/             # reverse proxy + TLS
│   └── doco-cd/             # gitops controller
├── scripts/                 # setup and maintenance
│   ├── setup.sh             # initial server setup
│   └── sync-secrets.sh      # update secrets
├── secrets.enc.env          # SOPS encrypted secrets
└── docs/                    # documentation
```

## Stack

| Component | Purpose |
|-----------|---------|
| [Docker Swarm](https://docs.docker.com/engine/swarm/) | Orchestration + rolling updates |
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps deployment |
| [Traefik](https://traefik.io) | Reverse proxy + TLS |
| [SOPS](https://github.com/getsops/sops) | Secrets encryption |

## Quick Start

```bash
# On your server
git clone https://github.com/wajeht/home-ops.git ~/home-ops
# Copy age key: scp ~/.sops/age-key.txt user@server:~/.sops/
cd ~/home-ops && ./scripts/setup.sh
```

See [Server Setup](docs/vps-setup.md) for full instructions.

## Documentation

- **[Server Setup](docs/vps-setup.md)** - Setting up a new server
- **[Secrets Management](docs/secrets.md)** - SOPS + Docker secrets
- **[Adding Apps](docs/adding-apps.md)** - Deploy new applications

## Quick Reference

### Add an app
```bash
mkdir -p apps/myapp
# Create apps/myapp/docker-compose.yml
git add -A && git commit -m "add myapp" && git push
# On server:
sudo docker stack deploy -c apps/myapp/docker-compose.yml myapp
```

### Add private ghcr app
```bash
# Same as above, but deploy with:
sudo docker stack deploy -c apps/myapp/docker-compose.yml --with-registry-auth myapp
```

### Edit secrets
```bash
sops secrets.enc.env
git push
ssh server 'cd ~/home-ops && ./scripts/sync-secrets.sh'
```

### Check services
```bash
ssh server 'sudo docker service ls'
```

### Force rolling update
```bash
ssh server 'sudo docker service update --force myapp_myapp'
```

### View logs
```bash
ssh server 'sudo docker service logs -f traefik_traefik'
```

## URLs

- https://home.wajeht.com - Dashboard
- https://traefik.wajeht.com - Traefik
- https://whoami.wajeht.com - Test
- https://commit.wajeht.com - AI Commits
