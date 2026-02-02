# home-ops

GitOps for Docker Swarm using [doco-cd](https://github.com/kimdre/doco-cd).

Zero-downtime rolling updates via Swarm mode.

## Structure

```
home-ops/
├── .doco-cd.yml        # root orchestrator
├── infrastructure/     # core services (traefik, doco-cd)
└── apps/               # application stacks
```

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
vim .env

# 2. Bootstrap (initializes swarm + deploys infra)
make bootstrap

# 3. Push to git - doco-cd handles the rest
git add . && git commit -m "init" && git push
```

## Zero-Downtime Deployments

All apps use Swarm rolling updates:

```yaml
deploy:
  replicas: 2
  update_config:
    parallelism: 1
    delay: 10s
    order: start-first      # new container starts before old stops
    failure_action: rollback
```

- `order: start-first` ensures new replica is healthy before stopping old
- `failure_action: rollback` auto-reverts on failure
- Set `REPLICAS=2` in `.env` (minimum for zero-downtime)

## Usage

### Add New App

```bash
mkdir apps/myapp
# create apps/myapp/docker-compose.yml (see template below)
git add . && git commit -m "add myapp" && git push
# deployed within 60s with zero downtime
```

### Remove App

```bash
rm -rf apps/myapp
git add . && git commit -m "remove myapp" && git push
# removed within 60s
```

### App Template

```yaml
services:
  myapp:
    image: myimage:latest
    hostname: myapp
    networks:
      - traefik
    deploy:
      mode: replicated
      replicas: ${REPLICAS:-2}
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
      rollback_config:
        parallelism: 1
        delay: 10s
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
        - "traefik.http.routers.myapp.entrypoints=websecure"
        - "traefik.http.routers.myapp.tls=true"
        - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
        - "traefik.http.services.myapp.loadbalancer.server.port=8080"

networks:
  traefik:
    external: true
```

## Subdomains & Routing

Set `DOMAIN` in `.env`:

```bash
DOMAIN=example.com
```

Results in:
- `whoami.example.com` → whoami
- `home.example.com` → homepage
- `traefik.example.com` → dashboard
- `doco.example.com` → doco-cd

## HTTPS / TLS

Using Let's Encrypt with Cloudflare DNS challenge (works behind NAT).

### Setup

1. Create Cloudflare API token with `Zone:DNS:Edit` permission
2. Configure `.env`:
   ```bash
   DOMAIN=yourdomain.com
   ACME_EMAIL=you@email.com
   CF_DNS_API_TOKEN=your_cloudflare_token
   ```
3. Traefik auto-provisions certs

### Other DNS Providers

Edit `infrastructure/traefik/docker-compose.yml`, change provider:
- `cloudflare`, `route53`, `digitalocean`, `duckdns`, `namecheap`

Full list: https://doc.traefik.io/traefik/https/acme/#providers

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Init swarm + deploy traefik + doco-cd |
| `make status` | Show stacks and services |
| `make ps` | Show service tasks |
| `make logs` | Tail doco-cd logs |
| `make deploy APP=path` | Deploy specific stack |
| `make down APP=path` | Remove specific stack |
| `make scale SVC=name REPLICAS=n` | Scale a service |
| `make pull` | Pull latest images |
| `make services` | List all services |
| `make nodes` | List swarm nodes |
| `make clean` | Remove all + prune |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TZ` | Timezone |
| `DOMAIN` | Base domain for routing |
| `GIT_ACCESS_TOKEN` | GitHub/Gitea token |
| `GITOPS_REPO_URL` | This repo's clone URL |
| `ACME_EMAIL` | Let's Encrypt email |
| `CF_DNS_API_TOKEN` | Cloudflare API token |
| `REPLICAS` | Default replica count (2 for zero-downtime) |

## How It Works

1. **Docker Swarm** manages containers with rolling updates
2. **doco-cd** polls this repo every 60s
3. Detects changes → deploys as Swarm stacks
4. **Traefik** handles routing + TLS + load balancing
5. Updates roll out with zero downtime

## Architecture

```
                    ┌─────────────┐
                    │   GitHub    │
                    └──────┬──────┘
                           │ poll every 60s
                    ┌──────▼──────┐
                    │   doco-cd   │
                    └──────┬──────┘
                           │ docker stack deploy
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌────────┐   ┌────────┐   ┌────────┐
         │ app-1  │   │ app-2  │   │ app-n  │
         │ (2 rep)│   │ (2 rep)│   │ (2 rep)│
         └────┬───┘   └────┬───┘   └───┬────┘
              └────────────┼───────────┘
                    ┌──────▼──────┐
                    │   traefik   │◄─── HTTPS
                    └─────────────┘
```
