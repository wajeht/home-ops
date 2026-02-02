# VPS Setup

Complete guide to setting up a new VPS from scratch.

## Prerequisites

- Fresh Ubuntu 24.04 VPS
- Root SSH access
- Domain pointing to VPS IP

## 1. Install Docker

```bash
curl -fsSL https://get.docker.com | sh
docker --version
```

## 2. Install SOPS

```bash
curl -LO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops
sops --version
```

## 3. Setup Secrets Directories

```bash
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops
```

## 4. Copy Age Key

From existing machine:
```bash
scp ~/.sops/age-key.txt root@NEW_VPS:/root/.sops/
```

Or generate new key (requires re-encrypting secrets):
```bash
age-keygen -o /root/.sops/age-key.txt
# Copy public key, update .sops.yaml, re-encrypt secrets.enc.env
```

## 5. Clone Repository

```bash
cd ~
git clone https://YOUR_TOKEN@github.com/wajeht/home-ops.git
```

## 6. Decrypt Secrets

```bash
cd ~/home-ops
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt

sops -d secrets.enc.env > /tmp/secrets.env

grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/webhook-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/cf-token
grep "^ACME_EMAIL=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/acme-email

rm /tmp/secrets.env
chmod 600 /root/.secrets/*
```

Verify:
```bash
ls -la /root/.secrets/
```

## 7. Bootstrap Infrastructure

```bash
# Create traefik network
docker network create traefik

# Start traefik (reverse proxy + TLS)
cd ~/home-ops/infrastructure/traefik
docker compose up -d

# Start doco-cd (GitOps controller)
cd ~/home-ops/infrastructure/doco-cd
docker compose up -d

# Verify
docker ps
```

## 8. Configure GitHub Webhook

1. Go to repo → Settings → Webhooks → Add webhook
2. Payload URL: `https://doco.yourdomain.com/v1/webhook`
3. Content type: `application/json`
4. Secret: (value from webhook-secret)
5. Events: Just the push event
6. Save

## 9. Update DNS

Point these to your VPS IP:
- `yourdomain.com`
- `*.yourdomain.com` (wildcard)

## 10. Verify Setup

```bash
# Check containers
docker ps

# Check traefik logs
docker logs traefik

# Check doco-cd logs
docker logs doco-cd

# Test webhook (push a commit)
```

## Troubleshooting

### Traefik not getting certificates
```bash
docker logs traefik 2>&1 | grep -i acme
```
- Check CF_DNS_API_TOKEN is correct
- Ensure DNS is pointing to VPS

### doco-cd not deploying
```bash
docker logs doco-cd
```
- Check GIT_ACCESS_TOKEN has repo read access
- Verify webhook secret matches GitHub

### Container won't start
```bash
docker compose logs
docker inspect <container>
```

## File Locations

```
/root/.sops/
└── age-key.txt              # SOPS decryption key (NEVER share)

/root/.secrets/
├── git-token                # GitHub PAT
├── webhook-secret           # Webhook authentication
├── apprise-url              # Discord webhook URL
├── cf-token                 # Cloudflare API token
└── acme-email               # Let's Encrypt email

~/home-ops/                  # Git repository
├── infrastructure/
│   ├── traefik/
│   └── doco-cd/
└── apps/
    └── */docker-compose.yml
```
