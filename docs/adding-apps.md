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
    restart: unless-stopped
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

## Security Hardening

All containers must drop all Linux capabilities and disable privilege escalation:

```yaml
cap_drop:
  - ALL
security_opt:
  - no-new-privileges:true
```

Most apps need `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` because they do user switching or chown on volumes at startup. Start with these and only remove them for truly stateless single-binary apps (Go/Node apps like authelia, miniflux, dozzle).

| Capability                                    | When needed                                                |
| --------------------------------------------- | ---------------------------------------------------------- |
| `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` | Most apps (user switching, writable volumes, init systems) |
| `NET_BIND_SERVICE`                            | App binds to port < 1024 (e.g., port 80)                   |
| `SETGID, SETUID`                              | Redis (only needs user switching, no file ownership)       |
| `DAC_READ_SEARCH, FOWNER`                     | Borgmatic (needs to read all files for backup)             |
| `NET_ADMIN`                                   | VPN containers (gluetun)                                   |

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

## Disable Rolling Deploy

For apps that cannot run multiple instances:

Create `apps/myapp/docker-cd.yml`:

```yaml
rolling_update: false
```

## Removing Apps

```bash
rm -rf apps/myapp
git add -A && git commit -m "remove myapp" && git push
```
