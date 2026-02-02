# home-ops

GitOps for Docker Compose using [doco-cd](https://github.com/kimdre/doco-cd).

## Structure

```
home-ops/
├── apps/                    # auto-discovered by doco-cd
│   ├── homepage/
│   ├── whoami/
│   └── prometheus/
├── infrastructure/          # core services (manual deploy)
│   ├── traefik/
│   └── doco-cd/
├── .doco-cd.yml             # auto-discover config
├── .sops.yaml               # sops encryption config
├── secrets.enc.env          # encrypted secrets (safe to commit)
└── renovate.json            # auto-update docker images
```

## Quick Start

```bash
# 1. Clone and configure
git clone https://github.com/wajeht/home-ops.git
cd home-ops
cp .env.example .env
nano .env  # fill in values

# 2. Bootstrap infrastructure
make bootstrap

# 3. Done - push to deploy
```

## How It Works

1. Push to `main` branch
2. GitHub webhook triggers doco-cd instantly
3. doco-cd auto-discovers `apps/*/docker-compose.yml`
4. Services deploy, Discord notification sent

## Adding Apps

Create `apps/myapp/docker-compose.yml`:

```yaml
services:
  myapp:
    image: myimage:v1.0.0
    restart: unless-stopped
    networks:
      - traefik
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.wajeht.com`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"
      - "traefik.http.services.myapp.loadbalancer.server.port=8080"

networks:
  traefik:
    external: true
```

Push - deployed automatically. No config needed (auto-discover).

## Secrets Management (SOPS)

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age).

### View encrypted secrets
```bash
cat secrets.enc.env  # shows encrypted values
```

### Edit secrets
```bash
# Decrypt, edit, re-encrypt in one command
sops secrets.enc.env
```

### Add new secret
```bash
sops secrets.enc.env
# Add your secret, save, auto-encrypts
```

### How it works
- `secrets.enc.env` - encrypted, safe to commit
- `.sops/age-key.txt` - private key, gitignored, on VPS at `/root/.sops/`
- doco-cd decrypts secrets at deploy time

### Setup on new machine
```bash
# Install tools
brew install age sops

# Copy age key from VPS (or generate new one)
mkdir -p .sops
scp root@YOUR_VPS:/root/.sops/age-key.txt .sops/
```

## Auto-Updates (Renovate)

[Renovate](https://github.com/apps/renovate) automatically creates PRs when docker images have updates.

- Detects pinned versions in docker-compose files
- Creates PR with version bump
- Merge PR → auto-deployed

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Setup traefik + doco-cd |
| `make status` | Show containers |
| `make logs` | Tail doco-cd logs |
| `sops secrets.enc.env` | Edit secrets |

## URLs

- https://home.wajeht.com - Homepage
- https://whoami.wajeht.com - Whoami
- https://traefik.wajeht.com - Traefik
- https://prometheus.wajeht.com - Prometheus
- https://doco.wajeht.com - doco-cd
