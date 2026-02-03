# Adding Apps

Push a docker-compose.yml → doco-cd auto-deploys with rolling updates.

## Quick Start

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
    deploy:
      replicas: 1
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
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

Push:
```bash
git add -A && git commit -m "add myapp" && git push
```

Done. doco-cd auto-deploys via webhook.

## With Secrets (SOPS)

doco-cd auto-decrypts `.enc.env` files on deployment.

```bash
# Create plain env file
cat > apps/myapp/.env << 'EOF'
DATABASE_URL=postgres://user:pass@host/db
API_KEY=secret123
EOF

# Encrypt it
sops -e apps/myapp/.env > apps/myapp/.enc.env
rm apps/myapp/.env
```

Reference in docker-compose.yml:
```yaml
services:
  myapp:
    image: myimage:v1.0
    env_file:
      - .enc.env    # doco-cd auto-decrypts
    networks:
      - traefik
    deploy:
      # ... labels and config
```

Edit secrets:
```bash
sops apps/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push
```

## Template Explained

### Labels (under deploy:)

```yaml
deploy:
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
    - "traefik.http.routers.myapp.entrypoints=websecure"
    - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
    - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

**Important:** Labels must be under `deploy:` for Swarm mode.

### Network

```yaml
networks:
  traefik:
    external: true
```

All apps must join the `traefik` network.

## With Volumes

```yaml
services:
  myapp:
    image: myimage:v1.0
    volumes:
      - myapp-data:/data
    networks:
      - traefik
    deploy:
      labels:
        # ... traefik labels

volumes:
  myapp-data:

networks:
  traefik:
    external: true
```

## With Environment Variables

```yaml
services:
  myapp:
    image: myimage:v1.0
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
    networks:
      - traefik
    deploy:
      # ...
```

## Private ghcr.io Images

```yaml
services:
  myapp:
    image: ghcr.io/username/myapp:v1.0
    # ... rest of config
```

The GH_TOKEN in `infra/doco-cd/.enc.env` handles authentication.

## Health Checks

```yaml
services:
  myapp:
    image: myimage:v1.0
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 5s
      retries: 3
```

## Removing Apps

```bash
rm -rf apps/myapp
git add -A && git commit -m "remove myapp" && git push
```

doco-cd will stop and remove the service.

## Pinning Image Versions

Always pin versions:

```yaml
# Good
image: nginx:1.25.3

# Bad
image: nginx:latest
```

## Multiple Services

```yaml
services:
  web:
    image: myapp-web:v1.0
    depends_on:
      - api
    networks:
      - traefik
      - internal
    deploy:
      labels:
        - "traefik.enable=true"
        # ...

  api:
    image: myapp-api:v1.0
    networks:
      - internal

networks:
  traefik:
    external: true
  internal:
```
