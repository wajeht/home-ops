# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age), stored per-app in git. docker-cd auto-decrypts during deployment.

## How It Works

```
apps/myapp/.env.sops  →  docker-cd auto-decrypts  →  container env vars
     encrypted            on deployment
     safe to commit
```

Each stack has its own `.env.sops` file. When docker-cd deploys (via polling), it automatically decrypts SOPS-encrypted files.

## Structure

```
apps/
├── bang/.env.sops
├── calendar/.env.sops
├── close-powerlifting/.env.sops
├── commit/.env.sops
├── gains/.env.sops
├── gitea/.env.sops
├── homepage/.env.sops
├── mm2us/.env.sops
├── notify/.env.sops
├── screenshot/.env.sops
├── traefik/.env.sops
├── vaultwarden/.env.sops
├── ...
├── vpn-qbit/.env.sops
└── ...
infra/
└── docker-cd/.env.sops
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
- Secrets passed as env vars at container runtime
