#!/bin/bash
# Remove all home-ops stacks and clean up
# Usage: ./scripts/uninstall.sh
set -eo pipefail

echo "=== home-ops Uninstall ==="
echo "This will remove ALL stacks, secrets, volumes, and images."
read -p "Continue? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

echo "[1/5] Removing stacks..."
$SUDO docker stack ls --format '{{.Name}}' | xargs -r -I{} $SUDO docker stack rm {}

echo "[2/5] Waiting for services to stop..."
sleep 15
# Wait for all services to fully stop
while [ "$($SUDO docker service ls -q | wc -l)" -gt 0 ]; do
    echo "Waiting for services to stop..."
    sleep 5
done

echo "[3/5] Removing secrets..."
$SUDO docker secret ls -q | xargs -r $SUDO docker secret rm

echo "[4/5] Removing configs..."
$SUDO docker config ls -q | xargs -r $SUDO docker config rm

echo "[5/5] Pruning..."
$SUDO docker network prune -f
$SUDO docker volume prune -af
$SUDO docker system prune -af

# Stop vpn-qbit (docker-compose)
cd ~/home-ops/apps/vpn-qbit 2>/dev/null && $SUDO docker compose down -v 2>/dev/null || true

echo ""
echo "=== Done ==="
$SUDO docker service ls
$SUDO docker secret ls
