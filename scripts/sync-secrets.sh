#!/bin/bash
# Sync secrets from git to Docker secrets
# Run after editing secrets.enc.env locally and pushing
set -e

# Determine home directory and if we need sudo
if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="$HOME"
    SUDO="sudo"
fi

REPO_DIR="$HOME_DIR/home-ops"
cd "$REPO_DIR" || { echo "Error: $REPO_DIR not found"; exit 1; }

echo "==> Pulling latest..."
git pull

echo "==> Decrypting secrets..."
export SOPS_AGE_KEY_FILE=$HOME_DIR/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

# Extract to temp files
grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /tmp/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /tmp/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /tmp/cf-token
GHCR_TOKEN=$(grep "^GHCR_TOKEN=" /tmp/secrets.env | cut -d= -f2)

# Create docker config for private registry
AUTH=$(printf "wajeht:%s" "$GHCR_TOKEN" | base64)
echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$AUTH\"}}}" > /tmp/docker-config.json

echo "==> Updating Docker secrets..."
# Remove and recreate secrets
for secret in git_token webhook_secret api_secret apprise_url cf_token sops_age_key docker_config; do
    $SUDO docker secret rm "$secret" 2>/dev/null || true
done

$SUDO docker secret create git_token /tmp/git-token
$SUDO docker secret create webhook_secret /tmp/webhook-secret
$SUDO docker secret create api_secret /tmp/api-secret
$SUDO docker secret create apprise_url /tmp/apprise-url
$SUDO docker secret create cf_token /tmp/cf-token
$SUDO docker secret create sops_age_key $HOME_DIR/.sops/age-key.txt
$SUDO docker secret create docker_config /tmp/docker-config.json

# Update ghcr login
echo "==> Updating ghcr.io login..."
echo "$GHCR_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin

# Cleanup
rm -f /tmp/secrets.env /tmp/git-token /tmp/webhook-secret /tmp/api-secret /tmp/apprise-url /tmp/cf-token /tmp/docker-config.json

echo "==> Triggering service updates..."
$SUDO docker service update --force doco-cd_doco-cd 2>/dev/null || true
$SUDO docker service update --force doco-cd_apprise 2>/dev/null || true
$SUDO docker service update --force traefik_traefik 2>/dev/null || true

echo "==> Done!"
echo ""
$SUDO docker secret ls
