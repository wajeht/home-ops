#!/bin/bash
# Update secrets and redeploy
# Run after editing .enc.env files and pushing
set -e

if [ "$EUID" -eq 0 ]; then
    HOME_DIR="/root"
    SUDO=""
else
    HOME_DIR="$HOME"
    SUDO="sudo"
fi

cd "$HOME_DIR/home-ops" || exit 1

echo "==> Pulling latest..."
git pull

export SOPS_AGE_KEY_FILE=$HOME_DIR/.sops/age-key.txt

# Update ghcr credentials
echo "==> Updating ghcr.io credentials..."
GHCR_TOKEN=$(sops -d infrastructure/doco-cd/.enc.env 2>/dev/null | grep "^GHCR_TOKEN=" | cut -d= -f2 || true)
if [ -n "$GHCR_TOKEN" ]; then
    AUTH=$(printf "wajeht:%s" "$GHCR_TOKEN" | base64)
    echo "{\"auths\":{\"ghcr.io\":{\"auth\":\"$AUTH\"}}}" > $HOME_DIR/.docker/config.json
    echo "$GHCR_TOKEN" | $SUDO docker login ghcr.io -u wajeht --password-stdin
fi

# Redeploy stacks with updated secrets
echo "==> Redeploying stacks..."
deploy() {
    local dir=$1 name=$2 registry=$3
    [ -f "$dir/.enc.env" ] && { eval "$(sops -d "$dir/.enc.env")"; export $(sops -d "$dir/.enc.env" | cut -d= -f1 | xargs); }
    if [ "$registry" = "true" ]; then
        HOME=$HOME_DIR $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" --with-registry-auth "$name"
    else
        HOME=$HOME_DIR $SUDO -E docker stack deploy -c "$dir/docker-compose.yml" "$name"
    fi
}

deploy infrastructure/traefik traefik
deploy infrastructure/doco-cd doco-cd
deploy apps/homepage homepage
deploy apps/whoami whoami
deploy apps/commit commit true

echo ""
echo "==> Done!"
$SUDO docker service ls
