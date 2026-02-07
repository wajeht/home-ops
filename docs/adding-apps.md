# Adding Apps

Push a docker-compose.yml → doco-cd auto-deploys.

## Swarm Apps (apps/swarm/)

For most apps. Gets rolling updates and zero-downtime deploys.

```bash
mkdir -p apps/swarm/myapp
```

Create `apps/swarm/myapp/docker-compose.yml`:
```yaml
services:
  myapp:
    image: nginx:1.25
    networks:
      - traefik
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
        - "traefik.http.routers.myapp.entrypoints=websecure"
        - "traefik.http.services.myapp.loadbalancer.server.port=80"
      update_config:
        order: start-first
      restart_policy:
        condition: on-failure

networks:
  traefik:
    external: true
```

## Compose Apps (apps/compose/)

For apps needing device access (e.g., `/dev/dri`, `/dev/net/tun`) which Swarm doesn't support.

```bash
mkdir -p apps/compose/myapp
```

Create `apps/compose/myapp/docker-compose.yml`:
```yaml
services:
  myapp:
    image: myimage:v1.0
    devices:
      - /dev/dri:/dev/dri
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
    restart: unless-stopped

networks:
  traefik:
    external: true
```

**Note:** Compose apps use container `labels:` (not `deploy.labels:`).

## Deploy

```bash
git add -A && git commit -m "add myapp" && git push
```

doco-cd auto-deploys via webhook/polling within 60s.

## With Secrets (SOPS)

doco-cd auto-decrypts `.enc.env` files on deployment.

```bash
# Create plain env file
cat > apps/swarm/myapp/.env << 'EOF'
DATABASE_URL=postgres://user:pass@host/db
API_KEY=secret123
EOF

# Encrypt it
sops -e apps/swarm/myapp/.env > apps/swarm/myapp/.enc.env
rm apps/swarm/myapp/.env
```

Reference in docker-compose.yml:
```yaml
services:
  myapp:
    image: myimage:v1.0
    env_file:
      - .enc.env    # doco-cd auto-decrypts
```

Edit secrets:
```bash
sops apps/swarm/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push
```

## Traefik Labels

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

TLS uses the wildcard cert (*.jaw.dev) automatically. No per-app `certresolver` needed.

**Swarm:** Labels under `deploy.labels:` | **Compose:** Labels under `labels:`

## Network

```yaml
networks:
  traefik:
    external: true
```

All apps must join the `traefik` network.

## Private ghcr.io Images

```yaml
services:
  myapp:
    image: ghcr.io/username/myapp:v1.0
```

The GH_TOKEN in `apps/infra/doco-cd/.enc.env` handles authentication.

## Removing Apps

```bash
rm -rf apps/swarm/myapp
git add -A && git commit -m "remove myapp" && git push
```

doco-cd will stop and remove the service (auto_discover with `delete: true`).

## Pinning Image Versions

Always pin versions:

```yaml
# Good
image: nginx:1.25.3

# Bad
image: nginx:latest
```
