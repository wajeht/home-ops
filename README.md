# home-ops

GitOps for Docker Swarm with zero-downtime rolling updates.

## Overview

Push to git → doco-cd auto-deploys → rolling update with no downtime.

```
home-ops/
├── apps/                    # applications
│   ├── homepage/            # dashboard
│   ├── whoami/              # test service
│   ├── commit/              # AI commit messages (private ghcr)
│   │   └── .enc.env         # app secrets (SOPS encrypted)
│   ├── gitea/               # git mirror
│   ├── uptime-kuma/         # status monitoring
│   └── plausible/           # privacy-friendly analytics
├── infrastructure/          # core services
│   ├── traefik/             # reverse proxy + TLS
│   │   └── .enc.env         # traefik secrets
│   └── doco-cd/             # gitops controller
│       └── .enc.env         # doco-cd secrets
├── scripts/                 # setup and maintenance
│   ├── setup.sh             # initial server setup
│   └── sync-secrets.sh      # redeploy after secret changes
└── docs/                    # documentation
```

## Stack

| Component | Purpose |
|-----------|---------|
| [Docker Swarm](https://docs.docker.com/engine/swarm/) | Orchestration + rolling updates |
| [doco-cd](https://github.com/kimdre/doco-cd) | GitOps deployment + SOPS decryption |
| [Traefik](https://traefik.io) | Reverse proxy + TLS |
| [SOPS](https://github.com/getsops/sops) | Per-app secrets encryption |
| [Gitea](https://gitea.io) | Git server + GitHub mirror |

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
- **[Secrets Management](docs/secrets.md)** - Per-app SOPS encryption
- **[Adding Apps](docs/adding-apps.md)** - Deploy new applications
- **[Renovate Auto-Updates](docs/renovate.md)** - Auto-update private images

## Quick Reference

### Add an app
```bash
mkdir -p apps/myapp
# Create apps/myapp/docker-compose.yml
git add -A && git commit -m "add myapp" && git push
```

### Add app with secrets
```bash
# Create encrypted env file
cat > apps/myapp/.env << 'EOF'
API_KEY=secret
EOF
sops -e apps/myapp/.env > apps/myapp/.enc.env
rm apps/myapp/.env

# Reference in docker-compose.yml:
# env_file:
#   - .enc.env

git add -A && git commit -m "add myapp" && git push
```

### Edit secrets
```bash
sops apps/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push
# doco-cd auto-deploys with decrypted secrets
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
- https://git.wajeht.com - Gitea (GitHub mirror)
- https://status.wajeht.com - Uptime Kuma
- https://analytics.wajeht.com - Plausible
