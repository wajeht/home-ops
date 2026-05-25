# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age), stored per-app in git. docker-cd auto-decrypts during deployment.

Use this doc when adding, viewing, or editing `.env.sops` files.

## How It Works

```
apps/myapp/.env.sops  →  docker-cd auto-decrypts  →  .env
     encrypted            on deployment
     safe to commit
```

Each stack has its own `.env.sops` file. When docker-cd deploys, it decrypts `.env.sops` to `.env`. Compose can use that file as container env vars or render values into runtime config files.

## Structure

```
apps/<app>/.env.sops
infra/<service>/.env.sops
```

## Local Setup

```bash
# Install
brew install age sops

# Get age key
mkdir -p ~/.sops
cp .sops/age-key.txt ~/.sops/  # or scp from server

# Configure
echo 'export SOPS_AGE_KEY_FILE=~/.sops/age-key.txt' >> ~/.zshrc
source ~/.zshrc
```

## Common Operations

### View secrets

```bash
sops -d apps/commit/.env.sops
```

### Edit secrets

```bash
sops apps/commit/.env.sops
# Make changes, save, auto re-encrypts
```

### Add secrets to new app

```bash
# Create plain .env
cat > apps/myapp/.env << 'EOF'
API_KEY=secret123
EOF

# Encrypt
sops -e apps/myapp/.env > apps/myapp/.env.sops
rm apps/myapp/.env

# Reference in compose
# env_file:
#   - .env
```

### Secret file from encrypted values

Use this when the app expects a file, not an env var.

```yaml
services:
  myapp:
    configs:
      - source: myapp_secret
        target: /run/secrets/myapp-secret.txt

configs:
  myapp_secret:
    content: |
      ${MYAPP_SECRET_VALUE}
```

### Deploy after changes

```bash
sops apps/myapp/.env.sops
git add -A && git commit -m "update secrets" && git push
```

docker-cd will auto-deploy with decrypted secrets.

## Special Files

- `~/.sops/age-key.txt` - Decryption key (never commit to public repo)
- `~/.docker/config.json` - Created from GH_TOKEN for private images

## Security Notes

- `.env.sops` files are safe to commit (encrypted)
- Plain `.env` files are gitignored
- docker-cd mounts age key at `/sops/age-key.txt`
- Secrets can be passed as env vars or rendered into runtime config files
