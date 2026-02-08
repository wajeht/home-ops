# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age), stored per-app in git. docker-cd auto-decrypts during deployment.

## How It Works

```
apps/myapp/.enc.env  →  docker-cd auto-decrypts  →  container env vars
     encrypted            on deployment
     safe to commit
```

Each stack has its own `.enc.env` file. When docker-cd deploys (via webhook/polling), it automatically decrypts SOPS-encrypted files.

## Structure

```
apps/
├── bang/.enc.env
├── calendar/.enc.env
├── close-powerlifting/.enc.env
├── commit/.enc.env
├── gains/.enc.env
├── gitea/.enc.env
├── homepage/.enc.env
├── mm2us/.enc.env
├── notify/.enc.env
├── screenshot/.enc.env
├── traefik/.enc.env
├── vaultwarden/.enc.env
├── ...
├── vpn-qbit/.enc.env
└── ...
infra/
└── docker-cd/.enc.env
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
sops -d apps/commit/.enc.env
```

### Edit secrets
```bash
sops apps/commit/.enc.env
# Make changes, save, auto re-encrypts
```

### Add secrets to new app
```bash
# Create plain .env
cat > apps/myapp/.env << 'EOF'
API_KEY=secret123
EOF

# Encrypt
sops -e apps/myapp/.env > apps/myapp/.enc.env
rm apps/myapp/.env

# Reference in compose
# env_file:
#   - .enc.env
```

### Deploy after changes
```bash
sops apps/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push
```

docker-cd will auto-deploy with decrypted secrets.

## Special Files

- `~/.sops/age-key.txt` - Decryption key (never commit to public repo)
- `~/.docker/config.json` - Created from GH_TOKEN for private images

## Security Notes

- `.enc.env` files are safe to commit (encrypted)
- Plain `.env` files are gitignored
- docker-cd mounts age key at `/sops/age-key.txt`
- Secrets passed as env vars at container runtime
