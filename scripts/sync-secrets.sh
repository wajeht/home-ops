#!/bin/bash
# Sync secrets from git to Docker secrets
# Run after editing secrets.enc.env locally and pushing
set -e

cd ~/home-ops || { echo "Error: ~/home-ops not found"; exit 1; }

echo "==> Pulling latest..."
git pull

echo "==> Decrypting secrets..."
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

# Extract to temp files
grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /tmp/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/cf-token

echo "==> Updating Docker secrets..."
# Remove and recreate secrets
for secret in git_token webhook_secret api_secret apprise_url cf_token sops_age_key; do
    docker secret rm "$secret" 2>/dev/null || true
done

docker secret create git_token /tmp/git-token
docker secret create webhook_secret /tmp/webhook-secret
docker secret create api_secret /tmp/api-secret
docker secret create apprise_url /tmp/apprise-url
docker secret create cf_token /tmp/cf-token
docker secret create sops_age_key /root/.sops/age-key.txt

# Cleanup
rm -f /tmp/secrets.env /tmp/git-token /tmp/webhook-secret /tmp/api-secret /tmp/apprise-url /tmp/cf-token

echo "==> Triggering service updates..."
# Force service update to pick up new secrets
docker service update --force doco-cd_doco-cd 2>/dev/null || true
docker service update --force doco-cd_apprise 2>/dev/null || true
docker service update --force traefik_traefik 2>/dev/null || true

echo "==> Done!"
echo ""
docker secret ls
