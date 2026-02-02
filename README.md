# home-ops

GitOps for Docker Compose using [doco-cd](https://github.com/kimdre/doco-cd).

## Structure

```
home-ops/
├── .doco-cd.yml           # deployment config
├── infrastructure/
│   ├── traefik/           # reverse proxy + TLS
│   ├── doco-cd/           # gitops controller
│   └── prometheus/        # metrics
└── apps/
    ├── homepage/
    └── whoami/
```

## Quick Start

```bash
# 1. On VPS: Install Docker
curl -fsSL https://get.docker.com | sh

# 2. Clone and configure
git clone https://github.com/wajeht/home-ops.git
cd home-ops
cp .env.example .env
nano .env  # fill in values

# 3. Bootstrap
make bootstrap

# 4. Done - doco-cd auto-deploys from git
```

## How It Works

1. **doco-cd** polls this repo every 60s
2. Detects changes in `.doco-cd.yml`
3. Runs `docker compose up -d` for each service
4. **Traefik** handles routing + TLS

## Adding Apps

1. Create `apps/myapp/docker-compose.yml`:

```yaml
services:
  myapp:
    image: myimage:latest
    container_name: myapp
    restart: unless-stopped
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"

networks:
  traefik:
    external: true
```

2. Add to `.doco-cd.yml`:

```yaml
---
name: myapp
working_dir: apps/myapp
compose_files:
  - docker-compose.yml
```

3. Push to git - deployed in ~60s

## Removing Apps

```bash
rm -rf apps/myapp
# remove from .doco-cd.yml
git add . && git commit -m "remove myapp" && git push
```

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Setup network + traefik + doco-cd |
| `make status` | Show containers |
| `make logs` | Tail doco-cd logs |
| `make deploy APP=path` | Deploy app |
| `make down APP=path` | Stop app |
| `make pull` | Pull latest images |
| `make clean` | Stop all + prune |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `GIT_ACCESS_TOKEN` | GitHub token (read-only) |
| `CF_DNS_API_TOKEN` | Cloudflare API token |

## URLs

- https://home.wajeht.com - Homepage
- https://whoami.wajeht.com - Whoami
- https://traefik.wajeht.com - Traefik Dashboard
- https://prometheus.wajeht.com - Prometheus
- https://doco.wajeht.com - doco-cd API
