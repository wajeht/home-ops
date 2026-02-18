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
      - proxy
    labels:
      caddy: myapp.jaw.dev
      caddy.import: auth
      caddy.reverse_proxy: "{{upstreams 80}}"
    restart: unless-stopped

networks:
  proxy:
    external: true
```

Use `caddy.import: auth` for protected apps. Use `caddy.import: public` for public apps.

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
  caddy: myapp.jaw.dev
  caddy.import: auth
  caddy.reverse_proxy: "{{upstreams 8080}}"
```

Public app:

```yaml
labels:
  caddy: myapp.jaw.dev
  caddy.import: public
  caddy.reverse_proxy: "{{upstreams 8080}}"
```

Path-based auth bypass:

```yaml
labels:
  caddy: myapp.jaw.dev
  caddy.handle_0: /webhook
  caddy.handle_0.reverse_proxy: "{{upstreams 8080}}"
  caddy.handle_1: "*"
  caddy.handle_1.import: auth
  caddy.handle_1.reverse_proxy: "{{upstreams 8080}}"
```

## Network

```yaml
networks:
  proxy:
    external: true
```

All internet-facing apps must join the `proxy` network.

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
