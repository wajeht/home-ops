#!/bin/bash
# Sync secrets from git to /root/.secrets/
# Run after editing secrets.enc.env locally and pushing
set -e

cd ~/home-ops || { echo "Error: ~/home-ops not found"; exit 1; }

echo "==> Pulling latest..."
git pull

echo "==> Decrypting secrets..."
export SOPS_AGE_KEY_FILE=/root/.sops/age-key.txt
sops -d secrets.enc.env > /tmp/secrets.env

grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/webhook-secret
grep "^API_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/api-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/cf-token
grep "^ACME_EMAIL=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/acme-email

rm /tmp/secrets.env
chmod 600 /root/.secrets/*

echo "==> Restarting services..."
cd infrastructure/doco-cd && docker compose restart
cd ../traefik && docker compose restart

echo "==> Done!"
