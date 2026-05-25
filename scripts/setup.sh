#!/bin/bash
# home-ops setup/management script
# Usage: ./scripts/setup.sh <command> [args]
set -eo pipefail

# Don't run as root - script uses sudo internally
[ "$EUID" -eq 0 ] && {
	echo "ERROR: Don't run with sudo. Script uses sudo internally."
	exit 1
}

# shellcheck source=scripts/utils.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

decrypt_dotenv_sops() {
	sops --decrypt --input-type dotenv --output-type dotenv "$1"
}

docker_relogin() {
	local secret_file="$REPO_DIR/infra/docker-cd/.env.sops"
	local decrypted=""
	local dh_user="" dh_token="" gh_token=""

	if [ ! -f "$secret_file" ]; then
		warn "Missing $secret_file, skipping docker registry login"
		return 0
	fi

	decrypted=$(decrypt_dotenv_sops "$secret_file")
	dh_user=$(printf '%s\n' "$decrypted" | grep "^DOCKER_HUB_USER=" | cut -d= -f2- || true)
	dh_token=$(printf '%s\n' "$decrypted" | grep "^DOCKER_HUB_TOKEN=" | cut -d= -f2- || true)
	gh_token=$(printf '%s\n' "$decrypted" | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2- || true)

	if [ -n "$dh_user" ] && [ -n "$dh_token" ]; then
		printf '%s' "$dh_token" | $SUDO docker login -u "$dh_user" --password-stdin
	else
		warn "DOCKER_HUB_USER/DOCKER_HUB_TOKEN missing, skipping docker.io login"
	fi

	if [ -n "$gh_token" ]; then
		printf '%s' "$gh_token" | $SUDO docker login ghcr.io -u wajeht --password-stdin
	else
		warn "GIT_ACCESS_TOKEN missing, skipping ghcr.io login"
	fi

	if [ "$EUID" -ne 0 ] && [ -f /root/.docker/config.json ]; then
		$SUDO install -m 600 /root/.docker/config.json "$USER_HOME/.docker/config.json"
	fi

	if [ -f "$USER_HOME/.docker/config.json" ]; then
		python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$USER_HOME/.docker/config.json"
	fi
}

sync_submodules() {
	local secret_file="$REPO_DIR/infra/docker-cd/.env.sops"
	local decrypted="" gh_token="" askpass="" rc=0

	[ ! -f .gitmodules ] && return 0

	info "Syncing git submodules..."

	if [ -f "$secret_file" ]; then
		decrypted=$(decrypt_dotenv_sops "$secret_file")
		gh_token=$(printf '%s\n' "$decrypted" | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2- || true)
	fi

	if [ -n "$gh_token" ]; then
		askpass=$(mktemp)
		cat >"$askpass" <<'EOF'
#!/bin/sh
case "$1" in
*Username*) printf '%s\n' "x-access-token" ;;
*Password*) printf '%s\n' "${GIT_ACCESS_TOKEN:-}" ;;
*) printf '\n' ;;
esac
EOF
		chmod 700 "$askpass"

		GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$askpass" GIT_ACCESS_TOKEN="$gh_token" git submodule sync --recursive || rc=$?
		if [ "$rc" -eq 0 ]; then
			GIT_TERMINAL_PROMPT=0 GIT_ASKPASS="$askpass" GIT_ACCESS_TOKEN="$gh_token" git submodule update --init --recursive || rc=$?
		fi

		rm -f "$askpass"
		return "$rc"
	fi

	GIT_TERMINAL_PROMPT=0 git submodule sync --recursive
	GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive
}

redeploy_compose() {
	local dir=$1 name=$2 force=${3:-0}
	local tmp="" env_backup="" had_env=0
	local compose_file="$dir/docker-compose.yml"
	local -a up_args=(-d)

	if [ "$force" = "1" ]; then
		up_args+=(--force-recreate)
	fi

	info "Redeploying $name..."

	if [ -f "$dir/.env.sops" ]; then
		tmp=$(mktemp)
		decrypt_dotenv_sops "$dir/.env.sops" >"$tmp"

		# Some stacks use env_file: .env, so materialize decrypted env during deploy.
		if [ -f "$dir/.env" ]; then
			had_env=1
			env_backup=$(mktemp)
			cp "$dir/.env" "$env_backup"
		fi
		cp "$tmp" "$dir/.env"

		if ! $SUDO docker compose -f "$compose_file" --project-directory "$dir" --env-file "$tmp" pull; then
			if [ "$had_env" = "1" ]; then
				cp "$env_backup" "$dir/.env"
			else
				rm -f "$dir/.env"
			fi
			rm -f "$env_backup"
			rm -f "$tmp"
			err "Failed to pull images for $name"
			return 1
		fi
		if ! $SUDO docker compose -f "$compose_file" --project-directory "$dir" --env-file "$tmp" up "${up_args[@]}"; then
			if [ "$had_env" = "1" ]; then
				cp "$env_backup" "$dir/.env"
			else
				rm -f "$dir/.env"
			fi
			rm -f "$env_backup"
			rm -f "$tmp"
			err "Failed to redeploy $name"
			return 1
		fi
		if [ "$had_env" = "1" ]; then
			cp "$env_backup" "$dir/.env"
		else
			rm -f "$dir/.env"
		fi
		rm -f "$env_backup"
		rm -f "$tmp"
	else
		if ! $SUDO docker compose -f "$compose_file" --project-directory "$dir" pull; then
			err "Failed to pull images for $name"
			return 1
		fi
		if ! $SUDO docker compose -f "$compose_file" --project-directory "$dir" up "${up_args[@]}"; then
			err "Failed to redeploy $name"
			return 1
		fi
	fi

	ok "$name redeployed"
}

# Config
USER_HOME="/home/jaw"
SUDO="sudo"
REPO_DIR="$USER_HOME/home-ops"
export SOPS_AGE_KEY_FILE="$USER_HOME/.sops/age-key.txt"

# SATA config (local secondary disk)
SATA_DEVICE="/dev/sda1"
SATA_MOUNT="/mnt/sata"
SATA_DIRS=(
	"$SATA_MOUNT/frigate/media"
)

# NFS config
NAS_IP="192.168.4.243"
NFS_MOUNTS=(
	"plex|/volume1/plex|$USER_HOME/plex"
	"backup|/volume1/backup|$USER_HOME/backup"
	"immich|/volume1/immich|$USER_HOME/immich"
)

# Static directories (not in compose files)
STATIC_DIRS=(
	"$USER_HOME/data/docker-cd"
	"$USER_HOME/data/dozzle"
	"$USER_HOME/plex/downloads"
	"$USER_HOME/plex/movies"
	"$USER_HOME/plex/tv"
	"$USER_HOME/plex/music"
	"$USER_HOME/plex/audiobooks"
	"$USER_HOME/plex/podcasts"
	"$USER_HOME/backup/borg"
	"$USER_HOME/.sops"
	"$USER_HOME/.docker"
)

ensure_external_networks() {
	# External networks/volumes used across stacks.
	$SUDO docker network create traefik 2>/dev/null || true
	$SUDO docker network create backup 2>/dev/null || true
	$SUDO docker network create media 2>/dev/null || true
	$SUDO docker volume create traefik-logs 2>/dev/null || true
}

#=============================================================================
# SETUP - Create directories
#=============================================================================
cmd_setup() {
	header "Mounts"
	sata_mount
	sata_persist
	cmd_nfs mount all
	cmd_nfs persist all

	header "Creating directories"
	local created=0 total=0

	# Create static dirs (not in compose files)
	info "Static directories..."
	for dir in "${STATIC_DIRS[@]}"; do
		total=$((total + 1))
		if [ ! -d "$dir" ]; then
			mkdir -p "$dir"
			dim "Created: $dir"
			created=$((created + 1))
		fi
	done

	# Auto-create ~/data/ and ~/backup/ dirs from compose volume mounts
	info "Scanning compose files for volume mounts..."
	local dirs
	dirs=$(sed -n "s|.*- \($USER_HOME/[^:]*\):.*|\1|p" "$REPO_DIR"/apps/*/docker-compose.yml "$REPO_DIR"/infra/*/docker-compose.yml 2>/dev/null | sort -u)
	local discovered=0
	for dir in $dirs; do
		discovered=$((discovered + 1))
		if [ ! -e "$dir" ]; then
			mkdir -p "$dir"
			dim "Created: $dir"
			created=$((created + 1))
		fi
	done
	dim "Found $discovered volume mounts across compose files"

	chmod 700 "$USER_HOME/.sops" 2>/dev/null || true
	# No blanket chown — containers handle internal ownership via CHOWN/FOWNER caps
	# Traefik runs as root in container (cap_drop: ALL removes DAC_OVERRIDE)
	# acme.json must be owned by root or Traefik can't read/write it
	$SUDO chown root:root "$USER_HOME/data/traefik/certs/acme.json" 2>/dev/null || true
	ok "Done ($created new, $((total + discovered)) total)"
}

#=============================================================================
# NFS - Mount/unmount NFS shares
#=============================================================================
nfs_mount() {
	local name=$1 nas_path=$2 local_path=$3
	if mountpoint -q "$local_path" 2>/dev/null; then
		dim "$name: Already mounted"
		return
	fi
	info "Mounting $name: $NAS_IP:$nas_path -> $local_path"
	mkdir -p "$local_path"
	if $SUDO mount -t nfs -o nconnect=4,rsize=1048576,wsize=1048576,noatime "$NAS_IP:$nas_path" "$local_path"; then
		ok "$name"
	else
		err "$name failed"
	fi
}

nfs_unmount() {
	local name=$1 nas_path=$2 local_path=$3
	info "Unmounting $name: $local_path"
	if $SUDO umount "$local_path" 2>/dev/null; then
		ok "$name"
	else
		dim "Not mounted"
	fi
}

nfs_status() {
	local name=$1 nas_path=$2 local_path=$3
	local mount_status fstab_status
	if mountpoint -q "$local_path" 2>/dev/null; then
		mount_status="${GREEN}MOUNTED${NC}   $(df -h "$local_path" | awk 'NR==2 {print $3"/"$2" ("$5" used)"}')"
	else
		mount_status="${RED}NOT MOUNTED${NC}"
	fi
	if grep -qF "$NAS_IP:$nas_path" /etc/fstab; then
		fstab_status="${GREEN}PERSISTED${NC}"
	else
		fstab_status="${DIM}NOT PERSISTED${NC}"
	fi
	printf "%-10s %b  %b\n" "$name:" "$mount_status" "$fstab_status"
}

nfs_persist() {
	local name=$1 nas_path=$2 local_path=$3
	# nconnect=4: 4 parallel TCP connections per mount (needs kernel 5.3+)
	# rsize/wsize=1048576: 1MB read/write chunks (server may negotiate lower)
	# noatime: skip access-time updates to reduce unnecessary NAS writes
	# x-systemd.before/required-by=docker.service: block docker until NFS is mounted,
	#   so containers don't bind-mount the empty placeholder dir on boot
	local opts="defaults,_netdev,nofail,nconnect=4,rsize=1048576,wsize=1048576,noatime,x-systemd.before=docker.service,x-systemd.required-by=docker.service"
	local entry="$NAS_IP:$nas_path $local_path nfs4 $opts 0 0"
	if grep -qxF "$entry" /etc/fstab; then
		dim "$name: already in fstab"
	else
		# Remove stale entries for same mount point (old IP, old options, etc.)
		$SUDO sed -i "\| $local_path |d" /etc/fstab
		echo "$entry" | $SUDO tee -a /etc/fstab >/dev/null
		ok "$name: added to fstab (run 'sudo systemctl daemon-reload' to apply)"
	fi
}

nfs_unpersist() {
	local name=$1 nas_path=$2 local_path=$3
	if grep -qF "$NAS_IP:$nas_path" /etc/fstab; then
		$SUDO sed -i "\|$NAS_IP:$nas_path|d" /etc/fstab
		ok "$name: removed from fstab"
	else
		dim "$name: not in fstab"
	fi
}

cmd_nfs() {
	local action=$1 target=${2:-all}
	[ -z "$action" ] && {
		echo -e "Usage: $0 nfs {mount|unmount|persist|unpersist|status} [plex|backup|all]"
		exit 1
	}

	for mount in "${NFS_MOUNTS[@]}"; do
		IFS='|' read -r name nas_path local_path <<<"$mount"
		if [[ "$target" == "all" || "$target" == "$name" ]]; then
			case "$action" in
				mount) nfs_mount "$name" "$nas_path" "$local_path" ;;
				unmount | umount) nfs_unmount "$name" "$nas_path" "$local_path" ;;
				persist) nfs_persist "$name" "$nas_path" "$local_path" ;;
				unpersist) nfs_unpersist "$name" "$nas_path" "$local_path" ;;
				status) nfs_status "$name" "$nas_path" "$local_path" ;;
			esac
		fi
	done
}

#=============================================================================
# SATA - Mount/unmount local SATA drive
#=============================================================================
sata_mount() {
	if mountpoint -q "$SATA_MOUNT" 2>/dev/null; then
		dim "sata: Already mounted"
		return
	fi
	if [ ! -b "$SATA_DEVICE" ]; then
		warn "SATA device $SATA_DEVICE not found, skipping"
		return
	fi
	info "Mounting SATA: $SATA_DEVICE -> $SATA_MOUNT"
	$SUDO mkdir -p "$SATA_MOUNT"
	if $SUDO mount "$SATA_DEVICE" "$SATA_MOUNT"; then
		# Create subdirectories
		for dir in "${SATA_DIRS[@]}"; do
			$SUDO mkdir -p "$dir"
		done
		$SUDO chown -R 1000:1000 "$SATA_MOUNT"
		ok "sata"
	else
		err "sata mount failed"
	fi
}

sata_unmount() {
	info "Unmounting SATA: $SATA_MOUNT"
	if $SUDO umount "$SATA_MOUNT" 2>/dev/null; then
		ok "sata"
	else
		dim "Not mounted"
	fi
}

sata_persist() {
	local entry="$SATA_DEVICE $SATA_MOUNT ext4 defaults 0 2"
	if grep -qF "$SATA_DEVICE" /etc/fstab; then
		dim "sata: already in fstab"
	else
		echo "$entry" | $SUDO tee -a /etc/fstab >/dev/null
		ok "sata: added to fstab"
	fi
}

sata_unpersist() {
	if grep -qF "$SATA_DEVICE" /etc/fstab; then
		$SUDO sed -i "\|$SATA_DEVICE|d" /etc/fstab
		ok "sata: removed from fstab"
	else
		dim "sata: not in fstab"
	fi
}

sata_status() {
	local mount_status fstab_status
	if mountpoint -q "$SATA_MOUNT" 2>/dev/null; then
		mount_status="${GREEN}MOUNTED${NC}   $(df -h "$SATA_MOUNT" | awk 'NR==2 {print $3"/"$2" ("$5" used)"}')"
	else
		mount_status="${RED}NOT MOUNTED${NC}"
	fi
	if grep -qF "$SATA_DEVICE" /etc/fstab; then
		fstab_status="${GREEN}PERSISTED${NC}"
	else
		fstab_status="${DIM}NOT PERSISTED${NC}"
	fi
	printf "%-10s %b  %b\n" "sata:" "$mount_status" "$fstab_status"
}

cmd_sata() {
	local action=${1:-status}
	case "$action" in
		mount) sata_mount ;;
		unmount | umount) sata_unmount ;;
		persist) sata_persist ;;
		unpersist) sata_unpersist ;;
		status) sata_status ;;
		*) echo -e "Usage: $0 sata {mount|unmount|persist|unpersist|status}" ;;
	esac
}

#=============================================================================
# INSTALL - Deploy all services
#=============================================================================
cmd_install() {
	header "home-ops Install"

	# Prerequisites
	step "1/4" "Checking prerequisites..."
	[ ! -f "$SOPS_AGE_KEY_FILE" ] && {
		err "Copy age key: scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$USER_HOME/.sops/"
		exit 1
	}
	[ ! -d "$REPO_DIR" ] && {
		err "Clone repo: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"
		exit 1
	}
	if ! command -v git &>/dev/null; then
		err "Install git first"
		exit 1
	fi

	# Install Docker
	step "2/4" "Docker..."
	if ! command -v docker &>/dev/null; then
		curl -fsSL https://get.docker.com | $SUDO sh
	fi
	if [ "$EUID" -ne 0 ]; then
		$SUDO usermod -aG docker "$USER"
		dim "Added $USER to docker group (re-login to take effect)"
	fi

	# Install SOPS
	if ! command -v sops &>/dev/null; then
		dim "Installing SOPS..."
		$SUDO curl -sLo /usr/local/bin/sops https://github.com/getsops/sops/releases/download/v3.11.0/sops-v3.11.0.linux.amd64
		$SUDO chmod +x /usr/local/bin/sops
	fi

	# Mount, persist, and create dirs
	step "3/4" "Mounts + Directories..."
	cmd_setup

	# Create external networks
	ensure_external_networks

	# Registry auth
	cd "$REPO_DIR"

	# Keep submodules in sync (e.g. apps/adguard) before deployments.
	sync_submodules

	docker_relogin

	# Deploy core services (order matters)
	step "4/4" "Deploying..."

	deploy_compose() {
		local dir=$1 name=$2
		local secret_file="" tmp=""
		info "Deploying $name..."
		cd "$dir"

		if [ -f .env.sops ]; then
			secret_file=".env.sops"
		fi

		if [ -n "$secret_file" ]; then
			tmp=$(mktemp)
			decrypt_dotenv_sops "$secret_file" >"$tmp"
			cp "$tmp" .env
			$SUDO docker compose --env-file "$tmp" up -d 2>/dev/null || warn "$name not started"
			rm -f "$tmp" .env
		else
			$SUDO docker compose up -d 2>/dev/null || warn "$name not started"
		fi
	}

	deploy_compose "$REPO_DIR/apps/traefik" traefik
	deploy_compose "$REPO_DIR/apps/google-auth" google-auth
	deploy_compose "$REPO_DIR/infra/docker-cd" docker-cd

	header "Done"
	echo ""
	echo -e "${BOLD}Containers:${NC}"
	$SUDO docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
	echo ""
	ok "docker-cd will auto-deploy remaining apps within 60s: ${CYAN}https://cd.jaw.dev${NC}"
}

reset_docker_cd_state() {
	local docker_cd_data_dir="$USER_HOME/data/docker-cd"

	info "Resetting docker-cd state/cache..."

	# Stop docker-cd first so it cannot rewrite state while files are removed.
	$SUDO docker stop docker-cd 2>/dev/null || true

	$SUDO rm -f "$docker_cd_data_dir/state.json" "$docker_cd_data_dir/history.json"
	$SUDO rm -rf "$docker_cd_data_dir/wajeht"

	ok "Cleared docker-cd state and repository cache"
}

#=============================================================================
# INSTALL-FRESH - Reset docker-cd state and re-run install
#=============================================================================
cmd_install_fresh() {
	reset_docker_cd_state
	cmd_install
}

#=============================================================================
# UNINSTALL - Remove all services
#=============================================================================
cmd_uninstall() {
	header "home-ops Uninstall"
	echo -e "${RED}This will remove ALL containers, networks, and prune images.${NC}"
	read -p "Continue? [y/N] " -n 1 -r
	echo
	[[ ! $REPLY =~ ^[Yy]$ ]] && exit 1

	# Stop core infra first to prevent re-deployments.
	step "1/4" "Stopping core infra..."
	(cd "$REPO_DIR/infra/docker-cd" 2>/dev/null && $SUDO docker compose down -v 2>/dev/null) || true
	(cd "$REPO_DIR/apps/google-auth" 2>/dev/null && $SUDO docker compose down -v 2>/dev/null) || true
	(cd "$REPO_DIR/apps/traefik" 2>/dev/null && $SUDO docker compose down -v 2>/dev/null) || true

	# Best-effort submodule sync so uninstall also sees submodule apps.
	if [ -f "$REPO_DIR/.gitmodules" ] && command -v git &>/dev/null; then
		(
			cd "$REPO_DIR"
			sync_submodules
		) || warn "Submodule sync failed, continuing uninstall"
	fi

	# Stop all app compose projects
	step "2/4" "Stopping all apps..."
	for dir in "$REPO_DIR"/apps/*/; do
		if [ -f "$dir/docker-compose.yml" ]; then
			dim "Stopping $(basename "$dir")..."
			(cd "$dir" && $SUDO docker compose down -v 2>/dev/null) || true
		fi
	done
	cd "$USER_HOME"

	step "3/4" "Removing networks..."
	for _ in 1 2 3; do
		$SUDO docker network prune -f 2>/dev/null || true
		$SUDO docker network rm traefik 2>/dev/null || true
		$SUDO docker network rm backup 2>/dev/null || true
		$SUDO docker network rm media 2>/dev/null || true
		sleep 2
	done

	step "4/4" "Pruning images..."
	$SUDO docker image prune -af 2>/dev/null || true
	$SUDO docker system prune -af 2>/dev/null || true

	header "Done"
	cmd_status
}

#=============================================================================
# STATUS - Show current status
#=============================================================================
cmd_status() {
	header "Status"
	echo ""
	echo -e "${BOLD}Containers:${NC}"
	$SUDO docker ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || dim "None"
	echo ""
	echo -e "${BOLD}SATA:${NC}"
	sata_status
	echo ""
	echo -e "${BOLD}NFS Mounts:${NC}"
	cmd_nfs status
	echo ""
	echo -e "${BOLD}Disk:${NC}"
	df -h "$USER_HOME/data" "$USER_HOME/plex" "$SATA_MOUNT" 2>/dev/null | tail -n +2 || true
}

#=============================================================================
# RELOGIN - Refresh docker registry auth
#=============================================================================
cmd_relogin() {
	header "Docker registry relogin"
	cd "$REPO_DIR"
	docker_relogin
	ok "Docker registry credentials refreshed"
}

#=============================================================================
# UPDATE-INFRA - Redeploy docker-cd (which manages all other services)
#=============================================================================
cmd_update_infra() {
	header "Updating infra"
	cd "$REPO_DIR"
	info "Pulling latest..."
	git pull

	# Keep submodules current after pull.
	sync_submodules || warn "Submodule sync failed, continuing"

	docker_relogin
	ensure_external_networks

	step "1/1" "Redeploying docker-cd..."
	redeploy_compose "$REPO_DIR/infra/docker-cd" docker-cd

	header "Done"
}

#=============================================================================
# UPDATE-INFRA-FORCE - Force recreate docker-cd (which manages all other services)
#=============================================================================
cmd_update_infra_force() {
	header "Updating infra (force recreate)"
	cd "$REPO_DIR"
	info "Pulling latest..."
	git pull

	# Keep submodules current after pull.
	sync_submodules || warn "Submodule sync failed, continuing"

	docker_relogin
	ensure_external_networks

	step "1/1" "Force-redeploying docker-cd..."
	redeploy_compose "$REPO_DIR/infra/docker-cd" docker-cd 1

	header "Done"
}

#=============================================================================
# IMAGES - Show/remove unused Docker images and volumes
#=============================================================================
cmd_images() {
	local action=${1:-status}
	header "Docker Cleanup"

	case "$action" in
		status)
			local running_file
			running_file=$(mktemp)
			docker ps --format '{{.ID}}' | while read -r cid; do
				docker inspect --format '{{.Image}}' "$cid" 2>/dev/null | sed 's/sha256://' | cut -c1-12
			done | sort -u >"$running_file"

			echo ""
			echo -e "${BOLD}Stale images (outdated, freed after next redeploy):${NC}"
			local stale_out
			stale_out=$(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' | awk -F'\t' '$3 == "<none>"' | while IFS=$'\t' read -r id repo _ size; do
				if grep -q "$id" "$running_file" 2>/dev/null; then
					printf "  %-45s %10s\n" "$repo" "$size"
				fi
			done)
			if [ -z "$stale_out" ]; then dim "None"; else echo "$stale_out"; fi

			echo ""
			echo -e "${BOLD}Prunable images (safe to remove now):${NC}"
			local prunable_out
			prunable_out=$(docker images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' | while IFS=$'\t' read -r id repo tag size; do
				grep -q "$id" "$running_file" 2>/dev/null || printf "  %-45s %10s\n" "$repo:$tag" "$size"
			done)
			if [ -z "$prunable_out" ]; then dim "None"; else echo "$prunable_out"; fi

			rm -f "$running_file"

			echo ""
			echo -e "${BOLD}Orphan volumes:${NC}"
			local total_vols orphan_vols
			total_vols=$(docker volume ls -q | wc -l)
			orphan_vols=$(docker volume ls -f dangling=true -q | wc -l)
			echo -e "  ${orphan_vols} orphan (${total_vols} total)"

			echo ""
			echo -e "${BOLD}Docker disk usage:${NC}"
			docker system df

			echo ""
			dim "Stale images free up after docker-cd redeploys those stacks"
			dim "Run '$0 images prune' to remove prunable images and orphan volumes"
			;;
		prune)
			info "Removing unused images..."
			docker image prune -af
			echo ""
			info "Removing orphan volumes..."
			docker volume prune -f
			echo ""
			info "Final state:"
			docker system df
			ok "Cleanup complete"
			;;
		*)
			echo -e "Usage: $0 images [status|prune]"
			;;
	esac
}

#=============================================================================
# UPDATE-SUBMODULES - Update submodules to latest and commit
#=============================================================================
cmd_update_submodules() {
	header "Updating submodules"
	cd "$REPO_DIR"

	[ ! -f .gitmodules ] && {
		warn "No submodules found"
		return 0
	}

	local updated=0
	# shellcheck disable=SC2016
	git submodule foreach --quiet 'echo $sm_path' | while read -r sm_path; do
		local name
		name=$(basename "$sm_path")
		info "Checking $name..."
		git submodule update --remote "$sm_path"
		if git diff --quiet "$sm_path"; then
			dim "$name: already up to date"
		else
			git add "$sm_path"
			git commit -m "chore($name): update submodule"
			ok "$name: updated"
			updated=$((updated + 1))
		fi
	done

	ok "Done"
}

#=============================================================================
# MAIN
#=============================================================================
print_usage() {
	echo -e "${BOLD}home-ops${NC} setup script"
	echo ""
	echo -e "Usage: ${CYAN}$0${NC} <command> [args]"
	echo ""
	echo -e "${BOLD}Commands:${NC}"
	echo -e "  ${GREEN}setup${NC}                    Create all data directories"
	echo -e "  ${GREEN}sata mount${NC}               Mount SATA drive (/mnt/sata)"
	echo -e "  ${GREEN}sata unmount${NC}             Unmount SATA drive"
	echo -e "  ${GREEN}sata persist${NC}             Add SATA mount to fstab (survives reboot)"
	echo -e "  ${GREEN}sata unpersist${NC}           Remove SATA mount from fstab"
	echo -e "  ${GREEN}sata status${NC}              Show SATA mount status"
	echo -e "  ${GREEN}nfs mount${NC} [target]       Mount NFS shares (plex|backup|all)"
	echo -e "  ${GREEN}nfs unmount${NC} [target]     Unmount NFS shares"
	echo -e "  ${GREEN}nfs persist${NC} [target]     Add NFS mounts to fstab (survives reboot)"
	echo -e "  ${GREEN}nfs unpersist${NC} [target]   Remove NFS mounts from fstab"
	echo -e "  ${GREEN}nfs status${NC}               Show NFS mount status"
	echo -e "  ${GREEN}install${NC}                  Deploy all services"
	echo -e "  ${GREEN}install-fresh${NC}            Reset docker-cd state, then deploy all services"
	echo -e "  ${GREEN}uninstall${NC}                Remove all services and cleanup"
	echo -e "  ${GREEN}relogin${NC}                  Refresh docker registry credentials"
	echo -e "  ${GREEN}update-infra${NC}             Redeploy docker-cd"
	echo -e "  ${GREEN}update-infra-force${NC}       Force-recreate docker-cd"
	echo -e "  ${GREEN}images${NC}                   Show unused Docker images and volumes"
	echo -e "  ${GREEN}images prune${NC}             Remove unused images (>7d) and orphan volumes"
	echo -e "  ${GREEN}update-submodules${NC}        Update submodules to latest and commit"
	echo -e "  ${GREEN}status${NC}                   Show containers, mounts, disk usage"
	echo ""
	echo -e "${BOLD}Examples:${NC}"
	echo -e "  ${DIM}$0 setup${NC}                 # Create directories"
	echo -e "  ${DIM}$0 nfs mount${NC}             # Mount all NFS shares"
	echo -e "  ${DIM}$0 nfs mount plex${NC}        # Mount only plex"
	echo -e "  ${DIM}$0 install${NC}               # Deploy everything"
	echo -e "  ${DIM}$0 install-fresh${NC}         # Force full docker-cd app reconcile"
	echo -e "  ${DIM}$0 update-infra-force${NC}    # Force-recreate infra containers"
	echo -e "  ${DIM}$0 status${NC}                # Show status"
}

case "${1:-}" in
	"" | help | -h | --help)
		print_usage
		exit 0
		;;
	setup)
		cmd_setup
		;;
	sata)
		shift
		cmd_sata "$@"
		;;
	nfs)
		shift
		cmd_nfs "$@"
		;;
	install)
		cmd_install
		;;
	install-fresh)
		cmd_install_fresh
		;;
	uninstall)
		cmd_uninstall
		;;
	status)
		cmd_status
		;;
	relogin)
		cmd_relogin
		;;
	update-infra)
		cmd_update_infra
		;;
	update-infra-force)
		cmd_update_infra_force
		;;
	images)
		shift
		cmd_images "$@"
		;;
	update-submodules)
		cmd_update_submodules
		;;
	*)
		print_usage
		exit 1
		;;
esac
