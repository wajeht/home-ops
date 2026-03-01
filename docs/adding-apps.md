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

## With Postgres (DB Dump Sidecar)

Apps with Postgres get a dump sidecar that uses the same postgres image (pg_dump version always matches). Dumps go to `~/data/<app>/dumps/` and borgmatic backs up `~/data/` daily.

```yaml
myapp-db:
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

myapp-db-dump:
  image: postgres:18-alpine@sha256:abc123 # same image as db
  environment:
    - PGPASSWORD=${POSTGRES_PASSWORD}
  entrypoint: ["/bin/sh", "-c"]
  command:
    - |
      echo "pg_dump sidecar for myapp"
      while true; do
        pg_dump -h myapp-db -U myapp -Fc myapp > /dumps/myapp.dump.tmp && mv /dumps/myapp.dump.tmp /dumps/myapp.dump && echo "dump ok $$(date)"
        sleep 86400
      done
  volumes:
    - /home/jaw/data/myapp/dumps:/dumps
  networks:
    - myapp-internal
  depends_on:
    myapp-db:
      condition: service_healthy
  restart: unless-stopped
  cap_drop:
    - ALL
  security_opt:
    - no-new-privileges:true
  deploy:
    resources:
      limits:
        cpus: "0.25"
        memory: 256M
```

### Per-App Borgmatic (DB Backup)

Each Postgres app also gets a borgmatic sidecar that backs up the dump to its own borg repo with independent retention and notifications.

Create `apps/myapp/borgmatic-config.yml`:

```yaml
source_directories:
  - /source/dumps

repositories:
  - path: /repository
    label: myapp

archive_name_format: "myapp-{now:%Y-%m-%d-%H%M%S}"
compression: zstd,3

keep_daily: 30
keep_weekly: 12
keep_monthly: 12

checks:
  - name: repository
    frequency: 1 week
  - name: archives
    frequency: 1 week

check_last: 3

ntfy:
  topic: borgmatic
  server: http://ntfy:80
  finish:
    title: "myapp db backup complete"
    message: "myapp database backup finished"
    priority: min
    tags: white_check_mark
  fail:
    title: "myapp db backup FAILED"
    message: "myapp database backup failed"
    priority: max
    tags: skull
  states:
    - finish
    - fail
```

Create `apps/myapp/borgmatic-crontab.txt` (pick a unique time slot):

```
0 1 * * * PATH=$PATH:/usr/local/bin /usr/local/bin/borgmatic --verbosity -2 --syslog-verbosity 1
```

Add borgmatic service to `docker-compose.yml`:

```yaml
myapp-borgmatic:
  image: ghcr.io/borgmatic-collective/borgmatic:2.1.2@sha256:961533d6135fd67736e9fee0f7cebc4926b57840d4a210be0a0cf2de6b004996
  env_file:
    - .env
  environment:
    - TZ=America/Chicago
  volumes:
    - /home/jaw/data/myapp/dumps:/source/dumps:ro
    - /home/jaw/backup/borg/myapp:/repository
    - /home/jaw/data/myapp/borgmatic:/borgmatic/state
    - ./borgmatic-config.yml:/etc/borgmatic/config.yaml:ro
    - ./borgmatic-crontab.txt:/etc/borgmatic.d/crontab.txt:ro
  networks:
    - traefik
  restart: unless-stopped
  cap_drop:
    - ALL
  cap_add:
    - DAC_READ_SEARCH
    - FOWNER
  security_opt:
    - no-new-privileges:true
  deploy:
    resources:
      limits:
        cpus: "0.5"
        memory: 512M
```

Add `BORG_PASSPHRASE` to the app's `.env.sops`.

### Per-App Borgmatic (SQLite)

SQLite apps use borgmatic's `sqlite_databases` hook for proper `.backup` dumps. Same pattern but different config and volume mounts.

Create `apps/myapp/borgmatic-config.yml`:

```yaml
sqlite_databases:
  - name: myapp
    path: /source/data/db.sqlite

repositories:
  - path: /repository
    label: myapp

archive_name_format: "myapp-{now:%Y-%m-%d-%H%M%S}"
compression: zstd,3

keep_daily: 30
keep_weekly: 12
keep_monthly: 12

checks:
  - name: repository
    frequency: 1 week
  - name: archives
    frequency: 1 week

check_last: 3

ntfy:
  topic: borgmatic
  server: http://ntfy:80
  finish:
    title: "myapp db backup complete"
    message: "myapp database backup finished"
    priority: min
    tags: white_check_mark
  fail:
    title: "myapp db backup FAILED"
    message: "myapp database backup failed"
    priority: max
    tags: skull
  states:
    - finish
    - fail
```

Add borgmatic service to `docker-compose.yml` (note: mounts data dir, not dumps):

```yaml
myapp-borgmatic:
  image: ghcr.io/borgmatic-collective/borgmatic:2.1.2@sha256:961533d6135fd67736e9fee0f7cebc4926b57840d4a210be0a0cf2de6b004996
  env_file:
    - .env
  environment:
    - TZ=America/Chicago
  volumes:
    - /home/jaw/data/myapp:/source/data
    - /home/jaw/backup/borg/myapp:/repository
    - /home/jaw/data/myapp/borgmatic:/borgmatic/state
    - ./borgmatic-config.yml:/etc/borgmatic/config.yaml:ro
    - ./borgmatic-crontab.txt:/etc/borgmatic.d/crontab.txt:ro
  networks:
    - traefik
  restart: unless-stopped
  cap_drop:
    - ALL
  cap_add:
    - DAC_READ_SEARCH
    - FOWNER
  security_opt:
    - no-new-privileges:true
  deploy:
    resources:
      limits:
        cpus: "0.5"
        memory: 512M
```

Add `BORG_PASSPHRASE` to the app's `.env.sops`.

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
