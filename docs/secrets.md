# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and stored in git. On the VPS, they're deployed as Docker Swarm secrets.

## How It Works

```
secrets.enc.env (git)  →  decrypt on VPS  →  docker secret create
     encrypted              SOPS               Swarm secrets
     safe to commit         age key            services read via /run/secrets/
```

## Local Setup (Dev Machine)

### Install Tools
```bash
brew install age sops
```

### Get Age Key
```bash
mkdir -p ~/.sops
scp root@YOUR_VPS:/root/.sops/age-key.txt ~/.sops/
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

### Deploy to VPS
After pushing changes:
```bash
ssh root@YOUR_VPS
cd ~/home-ops && ./scripts/sync-secrets.sh
```

## Docker Swarm Secrets

On the VPS, secrets are managed by Docker Swarm:

### List secrets
```bash
docker secret ls
```

### Inspect secret metadata
```bash
docker secret inspect cf_token
```

### Manually update a secret
```bash
# Remove old secret
docker secret rm my_secret

# Create new secret
echo "newvalue" | docker secret create my_secret -

# Update services to pick up change
docker service update --force service_name
```

## Current Secrets

| Secret | Docker Secret Name | Used By |
|--------|-------------------|---------|
| GIT_ACCESS_TOKEN | git_token | doco-cd |
| WEBHOOK_SECRET | webhook_secret | doco-cd |
| API_SECRET | api_secret | doco-cd |
| APPRISE_NOTIFY_URLS | apprise_url | doco-cd |
| CF_DNS_API_TOKEN | cf_token | traefik |
| (age key file) | sops_age_key | doco-cd |

## Rotating Secrets

### Rotate GitHub Token
1. Generate new token on GitHub
2. `sops secrets.enc.env` → update GIT_ACCESS_TOKEN
3. Push to git
4. On VPS: `./scripts/sync-secrets.sh`

### Rotate Webhook Secret
1. `openssl rand -hex 32` → generate new secret
2. `sops secrets.enc.env` → update WEBHOOK_SECRET
3. Push to git
4. Update GitHub webhook settings with new secret
5. On VPS: `./scripts/sync-secrets.sh`

### Rotate Age Key (Full Re-encryption)
```bash
# Generate new key
age-keygen -o new-age-key.txt

# Update .sops.yaml with new public key
# Re-encrypt secrets
sops -d secrets.enc.env > /tmp/plain.env
# Update .sops.yaml
sops -e /tmp/plain.env > secrets.enc.env
rm /tmp/plain.env

# Deploy new key to VPS
scp new-age-key.txt root@VPS:/root/.sops/age-key.txt

# Update Docker secret
ssh root@VPS 'docker secret rm sops_age_key && docker secret create sops_age_key /root/.sops/age-key.txt'

# Update local key
cp new-age-key.txt ~/.sops/age-key.txt
```

## Security Notes

- **Never commit** `/root/.sops/age-key.txt`
- Age key = master key. Protect it.
- Encrypted file safe to commit (can't decrypt without age key)
- Use minimal permissions for GitHub token (read-only)
- Docker secrets are encrypted at rest in the Swarm Raft log
