# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age) and stored in git.

## How It Works

```
secrets.enc.env (git)     →  decrypt on VPS  →  /root/.secrets/*
     encrypted                   SOPS                 plain files
     safe to commit              age key              Docker reads
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
# SSH to VPS
ssh root@YOUR_VPS

# Pull and decrypt
cd ~/home-ops && git pull
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

# Update specific secret file
grep "^MY_NEW_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/my-new-secret
chmod 600 /root/.secrets/my-new-secret
rm /tmp/secrets.env

# Restart service if needed
cd infrastructure/doco-cd && docker compose down && docker compose up -d
```

## Current Secrets

| Secret | File | Used By |
|--------|------|---------|
| GIT_ACCESS_TOKEN | git-token | doco-cd |
| WEBHOOK_SECRET | webhook-secret | doco-cd |
| APPRISE_NOTIFY_URLS | apprise-url | doco-cd |
| CF_DNS_API_TOKEN | cf-token | traefik |
| ACME_EMAIL | acme-email | traefik |

## Rotating Secrets

### Rotate GitHub Token
1. Generate new token on GitHub
2. `sops secrets.enc.env` → update GIT_ACCESS_TOKEN
3. Push to git
4. On VPS: decrypt and update `/root/.secrets/git-token`
5. Restart doco-cd

### Rotate Webhook Secret
1. `openssl rand -hex 32` → generate new secret
2. `sops secrets.enc.env` → update WEBHOOK_SECRET
3. Push to git
4. Update GitHub webhook settings with new secret
5. On VPS: decrypt and update `/root/.secrets/webhook-secret`
6. Restart doco-cd

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

# Update local key
cp new-age-key.txt ~/.sops/age-key.txt
```

## Security Notes

- **Never commit** `/root/.sops/age-key.txt` or `/root/.secrets/*`
- Age key = master key. Protect it.
- Encrypted file safe to commit (can't decrypt without age key)
- Use minimal permissions for GitHub token (read-only)
