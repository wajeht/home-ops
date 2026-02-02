#!/bin/bash
# Decrypt secrets.enc.env to /root/.secrets/
set -e

SOPS_KEY="${SOPS_AGE_KEY_FILE:-/root/.sops/age-key.txt}"

if [ ! -f "$SOPS_KEY" ]; then
    echo "Error: Age key not found at $SOPS_KEY"
    echo "Copy it from your local machine:"
    echo "  scp ~/.sops/age-key.txt root@THIS_VPS:/root/.sops/"
    exit 1
fi

if [ ! -f "secrets.enc.env" ]; then
    echo "Error: secrets.enc.env not found"
    echo "Run this script from the repo root: cd ~/home-ops"
    exit 1
fi

echo "==> Decrypting secrets..."
export SOPS_AGE_KEY_FILE="$SOPS_KEY"
sops -d secrets.enc.env > /tmp/secrets.env

echo "==> Creating secret files..."
mkdir -p /root/.secrets

grep "^GIT_ACCESS_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/git-token
grep "^WEBHOOK_SECRET=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/webhook-secret
grep "^APPRISE_NOTIFY_URLS=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/apprise-url
grep "^CF_DNS_API_TOKEN=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/cf-token
grep "^ACME_EMAIL=" /tmp/secrets.env | cut -d= -f2 > /root/.secrets/acme-email

rm /tmp/secrets.env
chmod 600 /root/.secrets/*

echo "==> Done! Secrets decrypted to /root/.secrets/"
ls -la /root/.secrets/
