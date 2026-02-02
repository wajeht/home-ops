#!/bin/bash
# Pull latest and update secrets (run on VPS after pushing changes)
set -e

echo "==> Pulling latest..."
git pull

echo "==> Decrypting secrets..."
./scripts/decrypt-secrets.sh

echo "==> Restarting doco-cd..."
cd infrastructure/doco-cd
docker compose down
docker compose up -d
cd ../..

echo "==> Done! Secrets updated and doco-cd restarted."
