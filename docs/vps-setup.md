# VPS Setup

## Quick Setup

```bash
# 1. SSH to fresh Ubuntu VPS
ssh root@YOUR_VPS

# 2. Run setup (installs Docker, SOPS, inits Swarm)
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

Done. Swarm running with infrastructure deployed.

## Post-Setup

1. **Update DNS** - Point `*.yourdomain.com` to VPS IP
2. **GitHub Webhook** - Add `https://doco.yourdomain.com/v1/webhook`
3. **Test** - Push a commit, verify rolling update with no downtime

## Verify Swarm

```bash
# Check swarm status
docker node ls

# Check secrets
docker secret ls

# Check stacks
docker stack ls

# Check services
docker service ls

# Check service logs
docker service logs traefik_traefik
docker service logs doco-cd_doco-cd
```

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

### Initialize Swarm
```bash
docker swarm init --advertise-addr $(hostname -I | awk '{print $1}')
```

### Setup Directories
```bash
mkdir -p /root/.secrets /root/.sops
chmod 700 /root/.secrets /root/.sops
```

### Decrypt and Create Secrets
```bash
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /tmp/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/cf-token

docker secret create git_token /tmp/git-token
docker secret create webhook_secret /tmp/webhook-secret
docker secret create api_secret /tmp/api-secret
docker secret create apprise_url /tmp/apprise-url
docker secret create cf_token /tmp/cf-token
docker secret create sops_age_key /root/.sops/age-key.txt

rm /tmp/secrets.env /tmp/git-token /tmp/webhook-secret /tmp/api-secret /tmp/apprise-url /tmp/cf-token
```

### Create Network and Deploy
```bash
docker network create --driver overlay --attachable traefik
cd infrastructure/traefik && docker stack deploy -c docker-compose.yml traefik
cd ../doco-cd && docker stack deploy -c docker-compose.yml doco-cd
```

## Troubleshooting

### Check logs
```bash
docker service logs traefik_traefik
docker service logs doco-cd_doco-cd
```

### Force service update
```bash
docker service update --force traefik_traefik
docker service update --force doco-cd_doco-cd
```

### Verify secrets
```bash
docker secret ls
```

### Rollback a service
```bash
docker service rollback traefik_traefik
```

### Leave Swarm (emergency rollback)
```bash
docker swarm leave --force
# Then use docker compose up -d manually
```

## File Locations

```
/root/.sops/age-key.txt      # Decryption key (NEVER share)
~/home-ops/                  # Git repository
```

Note: Secrets are now stored in Docker Swarm, not `/root/.secrets/`.
