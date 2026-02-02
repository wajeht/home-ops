# Adding Apps

Apps are auto-discovered by doco-cd. Just create a folder with docker-compose.yml.

## Quick Start

```bash
mkdir -p apps/myapp
```

Create `apps/myapp/docker-compose.yml`:
```yaml
services:
  myapp:
    image: nginx:1.25
    container_name: myapp
    restart: unless-stopped
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"

networks:
  traefik:
    external: true
```

Push:
```bash
git add -A && git commit -m "add myapp" && git push
```

Done. App deploys automatically via webhook.

## Template Explained

### Required Labels

```yaml
labels:
  # Enable traefik routing
  - "traefik.enable=true"

  # Domain routing rule
  - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"

  # Use HTTPS entrypoint
  - "traefik.http.routers.myapp.entrypoints=websecure"

  # Enable TLS with Let's Encrypt
  - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"

  # Container port (change to match your app)
  - "traefik.http.services.myapp.loadbalancer.server.port=8080"
```

### Required Network

```yaml
networks:
  traefik:
    external: true
```

All apps must join the `traefik` network to be routable.

## With Volumes

```yaml
services:
  myapp:
    image: myimage:v1.0
    restart: unless-stopped
    volumes:
      - myapp-data:/data
    networks:
      - traefik
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
    restart: unless-stopped
    environment:
      - NODE_ENV=production
      - LOG_LEVEL=info
    networks:
      - traefik
    labels:
      # ... traefik labels
```

## With App Secrets (SOPS)

For app-specific secrets, create encrypted env file:

```bash
# Create plain env file
cat > apps/myapp/secrets.env << 'EOF'
DATABASE_URL=postgres://user:pass@host/db
API_KEY=secret123
EOF

# Encrypt it
sops -e apps/myapp/secrets.env > apps/myapp/secrets.enc.env
rm apps/myapp/secrets.env
```

Reference in docker-compose.yml:
```yaml
services:
  myapp:
    image: myimage:v1.0
    env_file:
      - secrets.enc.env  # doco-cd auto-decrypts
    networks:
      - traefik
```

## Multiple Services

```yaml
services:
  web:
    image: myapp-web:v1.0
    restart: unless-stopped
    depends_on:
      - api
    networks:
      - traefik
      - internal
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
      # ...

  api:
    image: myapp-api:v1.0
    restart: unless-stopped
    networks:
      - internal

networks:
  traefik:
    external: true
  internal:
```

## Removing Apps

```bash
rm -rf apps/myapp
git add -A && git commit -m "remove myapp" && git push
```

doco-cd will stop and remove the containers.

## Pinning Image Versions

Always pin versions (Renovate will create PRs for updates):

```yaml
# Good
image: nginx:1.25.3

# Bad
image: nginx:latest
```

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
      start_period: 10s
```

## Common Patterns

### Static Site (nginx)
```yaml
services:
  site:
    image: nginx:1.25
    volumes:
      - ./html:/usr/share/nginx/html:ro
```

### Node.js App
```yaml
services:
  app:
    image: node:20-alpine
    working_dir: /app
    command: node server.js
    volumes:
      - ./:/app
```

### Database (internal only, no traefik)
```yaml
services:
  db:
    image: postgres:16
    restart: unless-stopped
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    networks:
      - internal  # NOT traefik

networks:
  internal:
```
