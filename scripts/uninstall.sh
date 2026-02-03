#!/bin/bash
# Remove all home-ops stacks and clean up
# Usage: ./scripts/uninstall.sh
set -eo pipefail

echo "=== home-ops Uninstall ==="
echo "This will remove ALL stacks, secrets, configs, volumes, and images."
read -p "Continue? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

SUDO=""
[ "$EUID" -ne 0 ] && SUDO="sudo"

# Stop vpn-qbit first (docker-compose, not swarm)
echo "[1/6] Stopping vpn-qbit..."
cd ~/home-ops/apps/vpn-qbit 2>/dev/null && $SUDO docker compose down -v 2>/dev/null || true
cd ~

echo "[2/6] Removing stacks..."
for stack in $($SUDO docker stack ls --format '{{.Name}}'); do
    echo "  Removing $stack..."
    $SUDO docker stack rm "$stack" 2>/dev/null || true
done

echo "[3/6] Waiting for services to stop..."
sleep 10
timeout=60
while [ "$($SUDO docker service ls -q 2>/dev/null | wc -l)" -gt 0 ] && [ $timeout -gt 0 ]; do
    echo "  Waiting... ($timeout s remaining)"
    sleep 5
    timeout=$((timeout - 5))
done

echo "[4/6] Removing secrets and configs..."
$SUDO docker secret ls -q 2>/dev/null | xargs -r $SUDO docker secret rm 2>/dev/null || true
$SUDO docker config ls -q 2>/dev/null | xargs -r $SUDO docker config rm 2>/dev/null || true

echo "[5/6] Removing networks..."
# Retry network removal (sometimes takes multiple attempts)
for i in 1 2 3; do
    $SUDO docker network prune -f 2>/dev/null || true
    # Remove specific overlay networks
    for net in traefik vpn-qbit_default; do
        $SUDO docker network rm "$net" 2>/dev/null || true
    done
    sleep 2
done

echo "[6/6] Pruning volumes and images..."
$SUDO docker volume prune -af 2>/dev/null || true
$SUDO docker image prune -af 2>/dev/null || true
$SUDO docker system prune -af 2>/dev/null || true

echo ""
echo "=== Done ==="
echo "Services:"
$SUDO docker service ls
echo ""
echo "Secrets:"
$SUDO docker secret ls
echo ""
echo "Volumes:"
$SUDO docker volume ls
