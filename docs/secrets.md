# Secrets Management

Secrets are encrypted with [SOPS](https://github.com/getsops/sops) + [age](https://github.com/FiloSottile/age), stored per-app in git. doco-cd auto-decrypts during deployment.

## How It Works

```
apps/swarm/myapp/.enc.env  →  doco-cd auto-decrypts  →  container env vars
     encrypted            on deployment
     safe to commit
```

Each stack has its own `.enc.env` file. When doco-cd deploys (via webhook/polling), it automatically decrypts SOPS-encrypted files.

## Structure

```
apps/swarm/
├── traefik/.enc.env         # CF_DNS_API_TOKEN
├── commit/.enc.env          # OPENAI_API_KEY, GEMINI_API_KEY, etc.
├── ...
apps/infra/
├── doco-cd/.enc.env         # GH_TOKEN, WEBHOOK_SECRET
└── doco-cd-compose/.enc.env # GH_TOKEN, WEBHOOK_SECRET
apps/compose/
└── vpn-qbit/.enc.env       # VPN credentials
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
sops -d apps/swarm/commit/.enc.env
```

### Edit secrets
```bash
sops apps/swarm/commit/.enc.env
# Make changes, save, auto re-encrypts
```

### Add secrets to new app
```bash
# Create plain .env
cat > apps/swarm/myapp/.env << 'EOF'
API_KEY=secret123
EOF

# Encrypt
sops -e apps/swarm/myapp/.env > apps/swarm/myapp/.enc.env
rm apps/swarm/myapp/.env

# Reference in compose
# env_file:
#   - .enc.env
```

### Deploy after changes
```bash
sops apps/swarm/myapp/.enc.env
git add -A && git commit -m "update secrets" && git push
```

doco-cd will auto-deploy with decrypted secrets.

## Special Files

- `~/.sops/age-key.txt` - Decryption key (never commit to public repo)
- `~/.docker/config.json` - Created from GH_TOKEN for private images

## Security Notes

- `.enc.env` files are safe to commit (encrypted)
- Plain `.env` files are gitignored
- doco-cd mounts age key at `/sops/age-key.txt`
- Secrets passed as env vars at container runtime
