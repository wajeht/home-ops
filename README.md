# home-ops

GitOps for Docker Swarm using [doco-cd](https://github.com/kimdre/doco-cd).

Zero-downtime rolling updates, secrets management, and full observability.

## Structure

```
home-ops/
├── .doco-cd.yml           # root orchestrator
├── .sops.yaml             # encryption config (optional)
├── infrastructure/        # core services
│   ├── traefik/           # reverse proxy + TLS
│   ├── doco-cd/           # gitops controller
│   └── prometheus/        # metrics
├── apps/                  # application stacks
│   ├── homepage/
│   └── whoami/
└── secrets/               # encrypted secrets (gitignored)
```

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
vim .env  # fill in values

# 2. Bootstrap
make bootstrap

# 3. Push to git - doco-cd handles the rest
git add . && git commit -m "init" && git push
```

## Features

| Feature | Implementation |
|---------|----------------|
| Zero-downtime deploys | Swarm rolling updates (`order: start-first`) |
| Automatic HTTPS | Let's Encrypt via Traefik |
| Secrets management | Docker secrets + SOPS encryption |
| Health checks | Container + Traefik load balancer checks |
| Metrics | Prometheus scraping Traefik + doco-cd |
| Notifications | Apprise (Discord, Slack, etc.) |
| Auto-rollback | `failure_action: rollback` |

## Zero-Downtime Deployments

All apps use Swarm rolling updates:

```yaml
deploy:
  replicas: 2                    # minimum for zero-downtime
  update_config:
    parallelism: 1               # update one at a time
    delay: 10s                   # wait between updates
    order: start-first           # start new before stopping old
    failure_action: rollback     # auto-revert on failure
    monitor: 30s                 # health check window
  restart_policy:
    condition: any
    max_attempts: 3
```

## Secrets Management

### Docker Secrets (Recommended)

Secrets are stored encrypted in Swarm and mounted to containers:

```bash
# Create secrets from .env
make secrets

# Update secrets
make secrets-update

# List secrets
make secrets-list
```

### SOPS Encryption (For Git)

Encrypt sensitive files before committing:

```bash
# Generate age key
make sops-keygen

# Add to .sops.yaml
creation_rules:
  - path_regex: \.env$
    age: >-
      age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx

# Encrypt
make sops-encrypt FILE=apps/myapp/.env

# doco-cd auto-decrypts during deployment
```

## App Template

```yaml
services:
  myapp:
    image: myimage:latest
    hostname: myapp-{{.Task.Slot}}
    environment:
      TZ: ${TZ:-America/Los_Angeles}
    networks:
      - traefik
    deploy:
      mode: replicated
      replicas: ${REPLICAS:-2}
      resources:
        limits:
          memory: 256M
        reservations:
          memory: 128M
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
        failure_action: rollback
        monitor: 30s
      rollback_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: any
        delay: 5s
        max_attempts: 3
        window: 120s
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
        - "traefik.http.routers.myapp.entrypoints=websecure"
        - "traefik.http.routers.myapp.tls=true"
        - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
        - "traefik.http.services.myapp.loadbalancer.server.port=8080"
        - "traefik.http.services.myapp.loadbalancer.healthcheck.path=/health"
        - "traefik.http.services.myapp.loadbalancer.healthcheck.interval=10s"
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s

networks:
  traefik:
    external: true
```

## Subdomains & Routing

Set `DOMAIN` in `.env`:

```bash
DOMAIN=example.com
```

Results:
| Subdomain | Service |
|-----------|---------|
| `home.example.com` | homepage |
| `whoami.example.com` | whoami |
| `traefik.example.com` | traefik dashboard |
| `doco.example.com` | doco-cd API |
| `prometheus.example.com` | prometheus |

## HTTPS / TLS

Using Let's Encrypt with Cloudflare DNS challenge:

1. Create Cloudflare API token with `Zone:DNS:Edit` permission
2. Add to `.env`:
   ```bash
   DOMAIN=yourdomain.com
   ACME_EMAIL=you@email.com
   CF_DNS_API_TOKEN=your_token
   ```

Other providers: `route53`, `digitalocean`, `duckdns`, `namecheap`
See: https://doc.traefik.io/traefik/https/acme/#providers

## Notifications

Configure in `.env`:

```bash
# Discord
APPRISE_NOTIFY_URLS=discord://webhook_id/webhook_token

# Slack
APPRISE_NOTIFY_URLS=slack://tokenA/tokenB/tokenC

# Multiple (comma-separated)
APPRISE_NOTIFY_URLS=discord://...,slack://...

# Notification level: info, success, warning, failure
APPRISE_NOTIFY_LEVEL=success
```

See: https://github.com/caronc/apprise/wiki

## API Endpoints

doco-cd exposes a REST API (requires `API_SECRET`):

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/health` | GET | Health check |
| `/v1/webhook` | POST | Git webhook receiver |
| `/v1/api/stacks` | GET | List stacks |
| `/v1/api/stack/{name}` | GET | Stack details |
| `/v1/api/stack/{name}` | DELETE | Remove stack |
| `/v1/api/stack/{name}/restart` | POST | Restart stack |
| `/v1/api/stack/{name}/scale` | POST | Scale stack |

Auth: `x-api-key: <API_SECRET>` header

## Commands

### Bootstrap
| Command | Description |
|---------|-------------|
| `make bootstrap` | Full setup (swarm + network + secrets + services) |
| `make swarm-init` | Initialize Docker Swarm |
| `make network` | Create overlay network |
| `make secrets` | Create Docker secrets |
| `make secrets-update` | Update secrets |

### Deployment
| Command | Description |
|---------|-------------|
| `make deploy APP=apps/myapp` | Deploy specific stack |
| `make down APP=apps/myapp` | Remove stack |
| `make scale SVC=myapp_web REPLICAS=3` | Scale service |
| `make restart SVC=myapp_web` | Force restart |

### Monitoring
| Command | Description |
|---------|-------------|
| `make status` | Show stacks and services |
| `make ps` | Show service tasks |
| `make logs` | Tail doco-cd logs |
| `make health` | Check service health |

### Maintenance
| Command | Description |
|---------|-------------|
| `make pull` | Pull latest images |
| `make up-all` | Deploy all stacks |
| `make down-all` | Remove all stacks |
| `make clean` | Remove all + prune |

## Environment Variables

| Variable | Description | Required |
|----------|-------------|----------|
| `TZ` | Timezone | No |
| `DOMAIN` | Base domain | Yes |
| `GITOPS_REPO_URL` | This repo's clone URL | Yes |
| `GIT_ACCESS_TOKEN` | Git provider token (read-only) | Yes |
| `API_SECRET` | doco-cd API auth | No |
| `WEBHOOK_SECRET` | Git webhook auth | No |
| `ACME_EMAIL` | Let's Encrypt email | Yes |
| `CF_DNS_API_TOKEN` | Cloudflare API token | Yes |
| `REPLICAS` | Default replica count | No (default: 2) |
| `APPRISE_NOTIFY_URLS` | Notification URLs | No |

## Architecture

```
                         ┌──────────────┐
                         │    GitHub    │
                         └──────┬───────┘
                                │ poll/webhook
                         ┌──────▼───────┐
                         │   doco-cd    │──────► Notifications
                         └──────┬───────┘
                                │ docker stack deploy
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
   ┌─────────┐            ┌─────────┐            ┌─────────┐
   │ app-1   │            │ app-2   │            │ app-n   │
   │ replica │            │ replica │            │ replica │
   │ replica │            │ replica │            │ replica │
   └────┬────┘            └────┬────┘            └────┬────┘
        └───────────────────────┼───────────────────────┘
                         ┌──────▼───────┐
                         │   traefik    │◄──── HTTPS (Let's Encrypt)
                         └──────┬───────┘
                                │
                         ┌──────▼───────┐
                         │  prometheus  │──────► Metrics
                         └──────────────┘
```

## Security Best Practices

1. **Minimal permissions** - Git tokens with read-only repo access
2. **Docker secrets** - Never put secrets in compose files or images
3. **SOPS encryption** - Encrypt secrets before committing to git
4. **Network isolation** - Apps only expose ports via Traefik
5. **Resource limits** - Prevent runaway containers
6. **Health checks** - Auto-restart unhealthy containers
7. **Read-only mounts** - `/var/run/docker.sock:ro` where possible
