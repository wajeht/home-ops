# Adding Apps

Push a docker-compose.yml → docker-cd auto-deploys.

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
      - .env.sops    # docker-cd auto-decrypts
```

Edit secrets:
```bash
sops apps/myapp/.env.sops
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

The server has docker login configured for ghcr.io.

## Disable Rolling Deploy

For apps that can't run multiple instances (e.g., BoltDB databases):

Create `apps/myapp/docker-cd.yml`:
```yaml
rolling_update: false
```

## Removing Apps

```bash
rm -rf apps/myapp
git add -A && git commit -m "remove myapp" && git push
```

docker-cd will stop and remove the service (garbage collection enabled).

## Pinning Image Versions

Always pin versions:

```yaml
# Good
image: nginx:1.25.3

# Bad
image: nginx:latest
```
