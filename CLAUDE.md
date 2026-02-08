# Claude Instructions

## Commit Rules

- Never add `Co-Authored-By:` to commit messages
- Always use conventional commit messages in a very short and concise way

## Data Storage

All persistent app data uses bind mounts to `~/data/` for easy backup:

```
~/data/                    # App configs/databases (backup this)
├── traefik/certs/
├── gitea/
├── vaultwarden/
├── media/{plex,radarr,sonarr,...}
├── miniflux/db/
└── ...

~/plex/                    # Media files (NFS from NAS)
├── movies/
├── tv/
├── downloads/
└── ...

~/.sops/age-key.txt        # SOPS decryption key (critical)
~/.docker/config.json      # Registry auth
```

### Backup

TBD

## SSL/TLS

Traefik uses Let's Encrypt wildcard cert for `*.jaw.dev`:
- Configured at entrypoint level (not per-app)
- Uses Cloudflare DNS challenge
- Apps don't need `certresolver` labels

## docker-cd

GitOps tool that auto-deploys Docker Compose stacks when git repo changes. Single instance replaces the old doco-cd + doco-cd-compose + apprise setup.

### How It Works

1. Polls git repo for changes
2. Reads `docker-cd.yml` from repo root for auto-discover config
3. Auto-discovers all `apps/*/docker-compose.yml` stacks
4. Auto-decrypts `.enc.env` files via SOPS
5. Deploys using `docker compose up` with rolling deploys

### Key Config

```yaml
# infra/docker-cd/docker-compose.yml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
  - ~/data/docker-cd:/data
  - ./poll-config.yml:/config/poll-config.yml:ro
  - ~/.sops/age-key.txt:/sops/age-key.txt:ro
  - ~/.docker/config.json:/root/.docker/config.json:ro
```

```yaml
# docker-cd.yml (repo root - auto-discover config)
auto_discover: true
auto_discover_opts:
  depth: 1
working_dir: apps
reference: main
rolling: true
force_image_pull: true
```

### Per-App Overrides

Apps can have a `docker-cd.yml` in their directory to override the root config:
```yaml
# apps/portainer/docker-cd.yml
rolling: false  # BoltDB can't handle 2 instances
```

### Architecture

- `apps/` - All application stacks (auto-discovered by docker-cd)
- `infra/docker-cd/` - docker-cd deployer (runs as compose, not auto-discovered)
- docker-cd source: `~/dev/docker-cd` — we own it, fix bugs/add features there
- Traefik uses Docker provider (reads container labels directly)
- All services run as Docker Compose

### Private ghcr.io Images

Server needs docker login:
```bash
echo 'TOKEN' | docker login ghcr.io -u USERNAME --password-stdin
```

Mount docker config: `~/.docker/config.json:/root/.docker/config.json:ro`

### Encrypted Secrets

docker-cd auto-decrypts `.enc.env` files if SOPS_AGE_KEY_FILE is set.

```bash
# Encrypt
sops -e .env > .enc.env

# Edit
sops .enc.env
```

### Notifications

Uses native Discord webhook notifications:
```yaml
# infra/docker-cd/.enc.env (SOPS encrypted)
NOTIFICATION_URL=https://discord.com/api/webhooks/<id>/<token>
```

## Renovate

Auto-updates Docker image versions in docker-compose.yml files.

### Flow

1. Push tag (e.g., `v1.0.0`) to app repo → GitHub Actions builds image to ghcr.io
2. Renovate detects new image version → auto-merges PR to home-ops
3. docker-cd detects home-ops change → deploys new version

### Config (renovate.json)

```json
{
  "hostRules": [{
    "matchHost": "ghcr.io",
    "hostType": "docker",
    "username": "wajeht",
    "password": "{{ secrets.GHCR_TOKEN }}"
  }],
  "packageRules": [{
    "matchDatasources": ["docker"],
    "matchPackageNames": ["/^ghcr\\.io/wajeht//"],
    "automerge": true,
    "automergeType": "branch"
  }]
}
```

### Private ghcr.io Access

GHCR_TOKEN needs `read:packages` scope (and `repo` for private repos).
Set in Mend Renovate dashboard under Secrets.
