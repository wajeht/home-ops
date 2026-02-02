# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and stored in git. On the server, they're deployed as Docker Swarm secrets.

## How It Works

```
secrets.enc.env (git)  →  decrypt on server  →  docker secret create
     encrypted              SOPS                  Swarm secrets
     safe to commit         age key               services read via /run/secrets/
```

## Current Secrets

| Secret | Docker Secret Name | Used By |
|--------|-------------------|---------|
| GIT_ACCESS_TOKEN | git_token | doco-cd |
| WEBHOOK_SECRET | webhook_secret | doco-cd |
| API_SECRET | api_secret | doco-cd |
| APPRISE_NOTIFY_URLS | apprise_url | doco-cd |
| CF_DNS_API_TOKEN | cf_token | traefik |
| GHCR_TOKEN | docker_config | doco-cd (private images) |
| (age key file) | sops_age_key | doco-cd |

## Local Setup (Dev Machine)

### Install Tools
```bash
brew install age sops
```

### Get Age Key
```bash
mkdir -p ~/.sops
scp user@YOUR_SERVER:~/.sops/age-key.txt ~/.sops/
```

### Configure Shell
```bash
echo 'export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt' >> ~/.zshrc
source ~/.zshrc
```

### Verify
```bash
sops secrets.enc.env
# Should open decrypted file in editor
```

## Common Operations

### View Secrets
```bash
sops -d secrets.enc.env
```

### Edit Secrets
```bash
sops secrets.enc.env
# Make changes, save, auto re-encrypts
```

### Add New Secret
```bash
sops secrets.enc.env
# Add line: MY_NEW_SECRET=myvalue
# Save and exit
git add secrets.enc.env
git commit -m "add new secret"
git push
```

### Deploy to Server
After pushing changes:
```bash
ssh user@YOUR_SERVER
cd ~/home-ops && ./scripts/sync-secrets.sh
```

## Private Registry (ghcr.io)

The `GHCR_TOKEN` is used to pull private images from GitHub Container Registry.

### Token Requirements
Create a GitHub **classic** token with `read:packages` scope.

### How It Works
1. `GHCR_TOKEN` stored in `secrets.enc.env`
2. `setup.sh` creates `docker_config` secret with base64-encoded auth
3. doco-cd mounts this at `/root/.docker/config.json`
4. Enables pulling private ghcr images during deployment

### Update GHCR Token
```bash
# Edit secrets locally
sops secrets.enc.env
# Update GHCR_TOKEN value, save

# Push and sync
git add -A && git commit -m "update ghcr token" && git push
ssh user@YOUR_SERVER 'cd ~/home-ops && ./scripts/sync-secrets.sh'
```

## Rotating Secrets

### Rotate GitHub Token
1. Generate new token on GitHub
2. `sops secrets.enc.env` → update GIT_ACCESS_TOKEN
3. Push to git
4. On server: `./scripts/sync-secrets.sh`

### Rotate GHCR Token
1. Generate new classic token with `read:packages`
2. `sops secrets.enc.env` → update GHCR_TOKEN
3. Push to git
4. On server: `./scripts/sync-secrets.sh`

### Rotate Age Key (Full Re-encryption)
```bash
# Generate new key
age-keygen -o new-age-key.txt

# Update .sops.yaml with new public key
# Re-encrypt secrets
sops -d secrets.enc.env > /tmp/plain.env
# Edit .sops.yaml with new age public key
sops -e /tmp/plain.env > secrets.enc.env
rm /tmp/plain.env

# Deploy new key to server
scp new-age-key.txt user@SERVER:~/.sops/age-key.txt

# Update Docker secret
ssh user@SERVER 'sudo docker secret rm sops_age_key && sudo docker secret create sops_age_key ~/.sops/age-key.txt'

# Update local key
cp new-age-key.txt ~/.sops/age-key.txt
```

## Security Notes

- **Never commit** `~/.sops/age-key.txt`
- Age key = master key. Protect it.
- Encrypted file safe to commit (can't decrypt without age key)
- Use minimal permissions for GitHub tokens
- Docker secrets are encrypted at rest in the Swarm Raft log
