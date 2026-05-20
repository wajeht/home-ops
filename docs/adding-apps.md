# Adding Apps

Push a `docker-compose.yml` to `apps/<name>/` and docker-cd auto-deploys it.

## Create App

```bash
mkdir -p apps/myapp
```

Create `apps/myapp/docker-compose.yml`:

```yaml
services:
  myapp:
    image: nginx:1.25
    networks:
      - traefik
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:80/healthz"]
      interval: 30s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    init: true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - CHOWN
      - DAC_OVERRIDE
      - FOWNER
      - NET_BIND_SERVICE # only if app listens on port < 1024
      - SETGID
      - SETUID
    security_opt:
      - no-new-privileges:true
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.middlewares=google-auth@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"

networks:
  traefik:
    external: true
```

Use `google-auth@file` for protected apps.
Omit auth middleware for public apps.

## Container Hardening

All containers must include these baseline configurations:

### Security

```yaml
read_only: true
tmpfs:
  - /tmp
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

`read_only: true` makes the container's root filesystem immutable — use on stateless single-binary apps (Go/Node) and wajeht/\* apps with data volumes. Add `tmpfs: /tmp` when the app might write temp files. Skip `read_only` for LSIO images, Postgres, Redis, borgmatic, and complex runtimes (Python/Elixir) that write all over the root filesystem.

Most apps need `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` because they do user switching or chown on volumes at startup. Start with these and only remove them for truly stateless single-binary apps (Go/Node apps like authelia, miniflux, dozzle).

| Capability                                    | When needed                                                |
| --------------------------------------------- | ---------------------------------------------------------- |
| `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` | Most apps (user switching, writable volumes, init systems) |
| `NET_BIND_SERVICE`                            | App binds to port < 1024 (e.g., port 80)                   |
| `SETGID, SETUID`                              | Redis (only needs user switching, no file ownership)       |
| `DAC_READ_SEARCH, FOWNER, SETGID, SETUID`     | Borgmatic (file reads + crond user switching)              |
| `NET_ADMIN`                                   | VPN containers (gluetun)                                   |

### Logging

All services must have log rotation to prevent disk fill:

```yaml
logging:
  driver: "json-file"
  options:
    max-size: "10m"
    max-file: "3"
```

### Resource Limits

All services must have CPU and memory limits:

```yaml
deploy:
  resources:
    limits:
      cpus: "0.5"
      memory: 256M
```

### Health Checks

All primary services must have a health check. Use `curl` or `wget` depending on what's available in the image:

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:80/healthz"]
  interval: 30s
  timeout: 5s
  retries: 3
```

Borgmatic sidecars use:

```yaml
healthcheck:
  test: ["CMD-SHELL", "borgmatic --version"]
  interval: 30s
  timeout: 10s
  retries: 3
```

### Init Process

Add `init: true` for proper signal handling and zombie process reaping. **Do NOT** add this to s6-overlay containers (borgmatic, LinuxServer.io images, homeassistant) — they require being PID 1.

```yaml
restart: unless-stopped
init: true # skip for s6-overlay containers
```

### PostgreSQL Services

Postgres containers should include extra settings for reliability:

```yaml
shm_size: 256m # prevent shared memory crashes (default 64MB is too low)
stop_grace_period: 30s # allow time for graceful shutdown
oom_score_adj: -300 # protect from OOM killer
```

### OOM Protection

Critical infrastructure gets `oom_score_adj: -500`, databases get `-300`. This ensures the OOM killer targets low-priority app containers first:

```yaml
# Critical infra (traefik, adguard, docker-cd, google-auth)
oom_score_adj: -500

# Databases (postgres, redis, clickhouse)
oom_score_adj: -300
```

## Deploy

```bash
git add -A && git commit -m "add myapp" && git push
```

docker-cd auto-deploys via polling (interval configured in `infra/docker-cd/docker-cd.yml`).

## With Secrets (SOPS)

docker-cd auto-decrypts `.env.sops` files on deployment.

```bash
# Create plain env file
cat > apps/myapp/.env << 'EOF'
DATABASE_URL=postgres://user:pass@host/db
API_KEY=secret123
EOF

# Encrypt it
sops -e apps/myapp/.env > apps/myapp/.env.sops
rm apps/myapp/.env
```

Reference in docker-compose.yml:

```yaml
services:
  myapp:
    image: myimage:v1.0
    env_file:
      - .env # docker-cd decrypts .env.sops -> .env
```

Edit secrets:

```bash
sops apps/myapp/.env.sops
git add -A && git commit -m "update secrets" && git push
```

## Routing Patterns

Private app:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.middlewares=google-auth@file"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

Public app:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

Path-based auth bypass:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.middlewares=google-auth@file"
  - "traefik.http.routers.myapp-webhook.rule=Host(`myapp.jaw.dev`) && Path(`/webhook`)"
  - "traefik.http.routers.myapp-webhook.entrypoints=websecure"
  - "traefik.http.routers.myapp-webhook.priority=100"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

## Network

```yaml
networks:
  traefik:
    external: true
```

All internet-facing apps must join the `traefik` network.

## Private ghcr.io Images

```yaml
services:
  myapp:
    image: ghcr.io/username/myapp:v1.0
```

The server has docker login configured for ghcr.io.

## With Postgres

Postgres service template. The DB container needs `container_name: <app>-db` set so [Backrest](disaster-recovery.md#adding-an-app) can `docker exec` into it for `pg_dump`.

```yaml
myapp-db:
  container_name: myapp-db
  image: postgres:18-alpine@sha256:abc123
  env_file:
    - .env
  environment:
    - POSTGRES_USER=myapp
    - POSTGRES_DB=myapp
    - PGDATA=/var/lib/postgresql/data
  volumes:
    - /home/jaw/data/myapp/db:/var/lib/postgresql/data
  networks:
    - myapp-internal
  healthcheck:
    test: ["CMD-SHELL", "pg_isready -U myapp"]
    interval: 30s
    timeout: 5s
    retries: 3
  restart: unless-stopped
  init: true
  shm_size: 256m
  stop_grace_period: 30s
  oom_score_adj: -300
  cap_drop:
    - ALL
  cap_add:
    - CHOWN
    - DAC_OVERRIDE
    - FOWNER
    - SETGID
    - SETUID
  security_opt:
    - no-new-privileges:true
  deploy:
    resources:
      limits:
        cpus: "0.5"
        memory: 256M
  logging:
    driver: "json-file"
    options:
      max-size: "10m"
      max-file: "3"
```

## Backup

To back up a new app, add a repo + plan to `apps/backrest/config/config.json`. Patterns and hook templates for Postgres, SQLite, and files-only apps are in [disaster-recovery.md → Adding an App](disaster-recovery.md#adding-an-app).

## Disable Rolling Deploy

For apps that cannot run multiple instances:

Create `apps/myapp/docker-cd.yml`:

```yaml
rolling_update: false
```

## Apps Behind Reverse Proxy (Trusted Proxies)

Some apps (e.g., Home Assistant) reject requests from reverse proxies unless explicitly configured. After first deploy, add the traefik network subnet as a trusted proxy in the app's config:

```yaml
# Home Assistant: ~/data/homeassistant/configuration.yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 172.18.0.0/16
```

Then restart the container. This is a one-time setup since the config persists in `~/data/`.

## Removing Apps

```bash
rm -rf apps/myapp
git add -A && git commit -m "remove myapp" && git push
```
