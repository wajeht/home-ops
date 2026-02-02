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
├── secrets.enc.env          # encrypted secrets (committed to git)
└── renovate.json            # auto-update docker images
```

## Quick Start (New VPS)

```bash
# 1. Install Docker
curl -fsSL https://get.docker.com | sh

# 2. Install SOPS
curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops && chmod +x /usr/local/bin/sops

# 3. Setup secrets directories
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops

# 4. Copy age key (get from existing machine or generate new)
# From existing: scp user@oldserver:/root/.sops/age-key.txt /root/.sops/
# Or generate: age-keygen -o /root/.sops/age-key.txt

# 5. Clone repo
git clone https://<TOKEN>@github.com/wajeht/home-ops.git
cd home-ops

# 6. Decrypt secrets
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env
grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/webhook-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/cf-token
grep "^ACME_EMAIL=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/acme-email
rm /tmp/secrets.env
chmod 600 /root/.secrets/*

# 7. Bootstrap
docker network create traefik
cd infrastructure/traefik && docker compose up -d
cd ../doco-cd && docker compose up -d
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

Push - deployed automatically via webhook.

## Secrets Management (SOPS)

All secrets are SOPS-encrypted in `secrets.enc.env` and committed to git.

### Edit secrets (local machine)
```bash
sops secrets.enc.env
# Edit, save - auto re-encrypts
```

### Deploy secrets to VPS
```bash
# On VPS after git pull
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env
# Parse into /root/.secrets/ files (see Quick Start step 6)
```

### Setup on new dev machine
```bash
brew install age sops
mkdir -p ~/.sops
scp root@YOUR_VPS:/root/.sops/age-key.txt ~/.sops/
echo 'export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt' >> ~/.zshrc
source ~/.zshrc
```

### Add new secret
```bash
sops secrets.enc.env
# Add: MY_NEW_SECRET=value
# Save, push, decrypt on VPS
```

## VPS Secrets Layout

```
/root/.sops/
└── age-key.txt           # SOPS decryption key

/root/.secrets/
├── git-token             # GitHub PAT
├── webhook-secret        # doco-cd webhook auth
├── apprise-url           # Discord notification URL
├── cf-token              # Cloudflare API token
└── acme-email            # Let's Encrypt email
```

## Auto-Updates (Renovate)

[Renovate](https://github.com/apps/renovate) creates PRs when docker images have updates.

Install: https://github.com/apps/renovate → Select repo

## Commands

| Command | Description |
|---------|-------------|
| `sops secrets.enc.env` | Edit encrypted secrets |
| `docker logs doco-cd` | Check deployment logs |
| `docker logs traefik` | Check proxy logs |

## URLs

- https://home.wajeht.com - Homepage
- https://whoami.wajeht.com - Whoami
- https://traefik.wajeht.com - Traefik
- https://prometheus.wajeht.com - Prometheus
- https://doco.wajeht.com - doco-cd
