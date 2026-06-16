# Adding Apps

Push a `docker-compose.yml` to `apps/<name>/` and docker-cd auto-deploys it.

For secrets, see [Secrets](secrets.md). For backups, see [Disaster Recovery](disaster-recovery.md#adding-an-app).

## Checklist

Before pushing a new app:

- `docker-compose.yml` lives in `apps/<name>/`
- docker-cd app config lives in top-level `x-docker-cd` inside Compose
- service has `restart`, `init`, healthcheck, logging, and resource limits
- container drops capabilities and uses `no-new-privileges`
- internet-facing app is on the external `traefik` network
- protected apps use `oauth2-admin@file`
- media apps use `oauth2-media@file`
- app data under `/home/jaw/data/<name>` has a Backrest plan unless intentionally ignored
- `./scripts/lint.sh` passes

## Create App

```bash
mkdir -p apps/myapp
```

Create `apps/myapp/docker-compose.yml`:

```yaml
x-docker-cd:
  rolling_update: false

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
      - "traefik.http.routers.myapp.middlewares=oauth2-admin@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"

networks:
  traefik:
    external: true
```

Use `oauth2-admin@file` for protected apps.
Omit auth middleware for public apps.

## Access Scopes

OAuth access is split by middleware:

- Admin apps use `oauth2-admin@file` and `OAUTH2_ADMIN_EMAIL_*` in `apps/oauth2-proxy/.env.sops`.
- Media apps use `oauth2-media@file` and `OAUTH2_MEDIA_EMAIL_*` in `apps/oauth2-proxy/.env.sops`.
- Current media hosts: `plex.jaw.dev`, `seerr.jaw.dev`, `convertx.jaw.dev`.

docker-cd decrypts the oauth2-proxy `.env.sops`; Docker Compose renders those email values into runtime allowlist files for oauth2-proxy. Do not commit plaintext email allowlist files.

Admin-only app:

```yaml
- "traefik.http.routers.myapp.middlewares=oauth2-admin@file"
```

Media app:

```yaml
- "traefik.http.routers.myapp.middlewares=oauth2-media@file"
```

Add/remove users by editing `apps/oauth2-proxy/.env.sops`.

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

`read_only: true` makes the container's root filesystem immutable. Use it unless the image or Compose feature needs rootfs writes. Add `tmpfs: /tmp` when the app might write temp files.

Most apps need `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` because they do user switching or chown on volumes at startup. Start with these and only remove them for truly stateless single-binary apps.

| Capability                                    | When needed                                                     |
| --------------------------------------------- | --------------------------------------------------------------- |
| `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` | Most apps that switch users, chown volumes, or use init systems |
| `NET_BIND_SERVICE`                            | App binds to port < 1024                                        |
| `SETGID, SETUID`                              | Redis user switching                                            |
| `NET_ADMIN`                                   | VPN containers (gluetun)                                        |

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

For scratch/minimal images with no shell, `curl`, or `wget`, either use the app's own healthcheck command or mount a static helper binary. See [apps/gatus/README.md → httpcheck Pattern](../apps/gatus/README.md#httpcheck-pattern).

To register the app for uptime monitoring and ntfy alerts, add an endpoint per [apps/gatus/README.md](../apps/gatus/README.md#adding-an-endpoint).

### Init Process

Add `init: true` for proper signal handling and zombie process reaping. **Do NOT** add this to s6-overlay containers such as LinuxServer.io images or Home Assistant; they require being PID 1.

```yaml
restart: unless-stopped
init: true # skip for s6-overlay containers
```

### PostgreSQL Services

Postgres containers should include extra settings for reliability:

```yaml
shm_size: 256m # default 64MB is too low
stop_grace_period: 30s # allow time for graceful shutdown
oom_score_adj: -300 # protect from OOM killer
```

### OOM Protection

Critical infrastructure gets `oom_score_adj: -500`, databases get `-300`. This ensures the OOM killer targets low-priority app containers first:

```yaml
# Critical infra: traefik, docker-cd, oauth2-proxy
oom_score_adj: -500

# Databases: postgres, redis, clickhouse
oom_score_adj: -300
```

## Deploy

```bash
./scripts/lint.sh
git add -A && git commit -m "add myapp" && git push
```

docker-cd auto-deploys via the interval in `apps/docker-cd/docker-compose.yml`.

## With Secrets

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

For apps that need a secret file instead of an env var, use Compose `configs.content` fed by the decrypted `.env`:

```yaml
services:
  myapp:
    configs:
      - source: myapp_secret
        target: /run/secrets/myapp-secret.txt

configs:
  myapp_secret:
    content: |
      ${MYAPP_SECRET_VALUE}
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
  - "traefik.http.routers.myapp.middlewares=oauth2-admin@file"
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
  - "traefik.http.routers.myapp.middlewares=oauth2-admin@file"
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

For apps that cannot run multiple instances, add top-level app config to `apps/myapp/docker-compose.yml`:

```yaml
x-docker-cd:
  rolling_update: false

services:
  myapp:
    image: nginx:1.25
```

## Apps Behind Reverse Proxy

Some apps reject requests from reverse proxies unless explicitly configured. After first deploy, add the traefik network subnet as a trusted proxy in the app's config:

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
./scripts/lint.sh
git add -A && git commit -m "remove myapp" && git push
```
