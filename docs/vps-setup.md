# VPS Setup

## Quick Setup

```bash
# 1. SSH to fresh Ubuntu VPS
ssh root@YOUR_VPS

# 2. Run setup (installs Docker + SOPS)
curl -fsSL https://raw.githubusercontent.com/wajeht/home-ops/main/scripts/setup.sh | bash
# Script will pause and tell you to copy age key

# 3. Copy age key (from your local machine)
scp ~/.sops/age-key.txt root@YOUR_VPS:/root/.sops/

# 4. Clone repo
git clone https://YOUR_TOKEN@github.com/wajeht/home-ops.git

# 5. Run setup again (now completes fully)
cd home-ops
./scripts/setup.sh
```

Done. Infrastructure running.

## Post-Setup

1. **Update DNS** - Point `*.yourdomain.com` to VPS IP
2. **GitHub Webhook** - Add `https://doco.yourdomain.com/v1/webhook`
3. **Test** - Push a commit, check Discord for notification

## Updating Secrets

After editing `secrets.enc.env` locally:

```bash
# Local: edit and push
sops secrets.enc.env
git add -A && git commit -m "update secrets" && git push

# VPS: sync
ssh root@YOUR_VPS
cd ~/home-ops && ./scripts/sync-secrets.sh
```

## Manual Setup

If you prefer step-by-step:

### Install Docker
```bash
curl -fsSL https://get.docker.com | sh
```

### Install SOPS
```bash
curl -sLO https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
mv sops-v3.11.0.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops
```

### Setup Directories
```bash
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops
```

### Decrypt Secrets
```bash
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

### Bootstrap
```bash
docker network create traefik
cd infrastructure/traefik && docker compose up -d
cd ../doco-cd && docker compose up -d
```

## Troubleshooting

### Check logs
```bash
docker logs traefik
docker logs doco-cd
```

### Restart services
```bash
cd ~/home-ops/infrastructure/traefik && docker compose restart
cd ~/home-ops/infrastructure/doco-cd && docker compose restart
```

### Verify secrets
```bash
ls -la /root/.secrets/
cat /root/.secrets/git-token  # should show token
```

## File Locations

```
/root/.sops/age-key.txt      # Decryption key (NEVER share)
/root/.secrets/*             # Decrypted secrets
~/home-ops/                  # Git repository
```
