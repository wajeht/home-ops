#!/bin/bash
# Bootstrap infrastructure (traefik + doco-cd)
set -e

# Check we're in the right directory
if [ ! -f ".doco-cd.yml" ]; then
    echo "Error: Run this from the repo root: cd ~/home-ops"
    exit 1
fi

# Check secrets exist
if [ ! -f "/root/.secrets/git-token" ]; then
    echo "Error: Secrets not found. Run ./scripts/decrypt-secrets.sh first"
    exit 1
fi

echo "==> Creating traefik network..."
docker network inspect traefik >/dev/null 2>&1 || docker network create traefik

echo "==> Starting traefik..."
cd infrastructure/traefik
docker compose up -d
cd ../..

echo "==> Starting doco-cd..."
cd infrastructure/doco-cd
docker compose up -d
cd ../..

echo "==> Waiting for services..."
sleep 5

echo "==> Status:"
docker ps --format "table {{.Names}}\t{{.Status}}"

echo ""
echo "==> Done! Infrastructure is running."
echo ""
echo "Next steps:"
echo "  1. Update DNS to point to this server"
echo "  2. Configure GitHub webhook: https://doco.yourdomain.com/v1/webhook"
echo "  3. Push a commit to test deployment"
