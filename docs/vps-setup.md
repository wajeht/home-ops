# Server Setup

## Quick Setup

```bash
# 1. SSH to your server
ssh user@YOUR_SERVER

# 2. Install Docker and SOPS
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker $USER
# Log out and back in

sudo curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
sudo chmod +x /usr/local/bin/sops

# 3. Copy age key (from your local machine)
mkdir -p ~/.sops
scp ~/.sops/age-key.txt user@YOUR_SERVER:~/.sops/

# 4. Clone repo
git clone https://github.com/wajeht/home-ops.git ~/home-ops

# 5. Run setup
cd ~/home-ops && ./scripts/setup.sh
```

## What Setup Does

1. Installs Docker and SOPS (if needed)
2. Initializes Docker Swarm
3. Sets up ghcr.io authentication
4. Creates overlay network
5. Deploys all stacks with decrypted per-app secrets

## DNS Configuration

### Local Network (AdGuard)
Add DNS rewrite in AdGuard Home:
- Domain: `*.jaw.dev`
- Answer: `192.168.x.x` (your server IP)

### Public Internet
Point `*.yourdomain.com` to your server's public IP.

## Verify Setup

```bash
# Check swarm
sudo docker node ls

# Check services
sudo docker service ls

# Check service logs
sudo docker service logs traefik_traefik
sudo docker service logs doco-cd_doco-cd
```

## Updating Secrets

```bash
# Local: edit and push
sops apps/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push

# doco-cd auto-deploys, or manually:
ssh user@YOUR_SERVER 'cd ~/home-ops && ./scripts/sync-secrets.sh'
```

## Deploying Apps

After initial setup, just push to git - doco-cd handles deployment.

### Manual deploy (if needed)
```bash
cd ~/home-ops && ./scripts/setup.sh
```

### Force update (rolling restart)
```bash
sudo docker service update --force appname_appname
```

## Troubleshooting

### Check logs
```bash
sudo docker service logs -f traefik_traefik
sudo docker service logs -f doco-cd_doco-cd
```

### Service not starting
```bash
sudo docker service ps appname_appname --no-trunc
```

### Rollback a service
```bash
sudo docker service rollback traefik_traefik
```

### Reset and redeploy
```bash
sudo docker stack rm appname
./scripts/setup.sh
```

## File Locations

```
~/.sops/age-key.txt      # Decryption key (NEVER commit)
~/.docker/config.json    # ghcr.io credentials
~/home-ops/              # Git repository
```
