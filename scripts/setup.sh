#!/bin/bash
# home-ops setup/management script
# Usage: ./scripts/setup.sh <command> [args]
set -euo pipefail

# Don't run as root - script uses sudo internally
[ "$EUID" -eq 0 ] && {
	printf '%s\n' "ERROR: Don't run with sudo. Script uses sudo internally."
	exit 1
}

# shellcheck source=scripts/utils.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"

decrypt_dotenv_sops() {
	require_cmd sops
	sops --decrypt --input-type dotenv --output-type dotenv "$1"
}

docker_cmd() {
	require_cmd docker
	if docker info >/dev/null 2>&1; then
		docker "$@"
	else
		$SUDO docker "$@"
	fi
}

docker_relogin() {
	local decrypted=""
	local dh_user="" dh_token="" gh_token=""

	if [ ! -f "$DOCKER_CD_SECRET_FILE" ]; then
		warn "Missing $DOCKER_CD_SECRET_FILE, skipping docker registry login"
		return 0
	fi

	decrypted=$(decrypt_dotenv_sops "$DOCKER_CD_SECRET_FILE")
	dh_user=$(printf '%s\n' "$decrypted" | grep "^DOCKER_HUB_USER=" | cut -d= -f2- || true)
	dh_token=$(printf '%s\n' "$decrypted" | grep "^DOCKER_HUB_TOKEN=" | cut -d= -f2- || true)
	gh_token=$(printf '%s\n' "$decrypted" | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2- || true)

	if [ -n "$dh_user" ] && [ -n "$dh_token" ]; then
		printf '%s' "$dh_token" | docker_cmd login -u "$dh_user" --password-stdin
	else
		warn "DOCKER_HUB_USER/DOCKER_HUB_TOKEN missing, skipping docker.io login"
	fi

	if [ -n "$gh_token" ]; then
		printf '%s' "$gh_token" | docker_cmd login ghcr.io -u wajeht --password-stdin
	else
		warn "GIT_ACCESS_TOKEN missing, skipping ghcr.io login"
	fi

	if ! docker info >/dev/null 2>&1 && [ "$EUID" -ne 0 ] && [ -f /root/.docker/config.json ]; then
		$SUDO install -m 600 /root/.docker/config.json "$USER_HOME/.docker/config.json"
	fi
}

sync_submodules() {
	local decrypted="" gh_token="" askpass="" tmp_dir="" rc=0

	[ ! -f .gitmodules ] && return 0

	require_cmd git
	info "Syncing git submodules..."

	if [ -f "$DOCKER_CD_SECRET_FILE" ]; then
		decrypted=$(decrypt_dotenv_sops "$DOCKER_CD_SECRET_FILE")
		gh_token=$(printf '%s\n' "$decrypted" | grep "^GIT_ACCESS_TOKEN=" | cut -d= -f2- || true)
	fi

	if [ -n "$gh_token" ]; then
		tmp_dir=$(mktemp -d)
		askpass="$tmp_dir/git-askpass"
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

		rm -rf "$tmp_dir"
		return "$rc"
	fi

	GIT_TERMINAL_PROMPT=0 git submodule sync --recursive
	GIT_TERMINAL_PROMPT=0 git submodule update --init --recursive
}

compose_cmd() {
	local dir=$1
	shift
	local tmp_dir="" env_file="" env_backup="" had_env=0 rc=0
	local compose_file="$dir/docker-compose.yml"

	if [ -f "$dir/.env.sops" ]; then
		tmp_dir=$(mktemp -d)
		env_file="$tmp_dir/env"
		if ! decrypt_dotenv_sops "$dir/.env.sops" >"$env_file"; then
			rm -rf "$tmp_dir"
			return 1
		fi

		# Some stacks use env_file: .env, so materialize decrypted env during deploy.
		if [ -f "$dir/.env" ]; then
			had_env=1
			env_backup="$tmp_dir/env.backup"
			cp "$dir/.env" "$env_backup"
		fi
		cp "$env_file" "$dir/.env"

		docker_cmd compose -f "$compose_file" --project-directory "$dir" --env-file "$env_file" "$@" || rc=$?

		if [ "$had_env" = "1" ]; then
			cp "$env_backup" "$dir/.env"
		else
			rm -f "$dir/.env"
		fi
		rm -rf "$tmp_dir"
		return "$rc"
	fi

	docker_cmd compose -f "$compose_file" --project-directory "$dir" "$@"
}

deploy_compose() {
	local dir=$1 name=$2
	info "Deploying $name..."
	compose_cmd "$dir" up -d 2>/dev/null || warn "$name not started"
}

redeploy_compose() {
	local dir=$1 name=$2 force=${3:-0}
	local -a up_args=(-d)

	if [ "$force" = "1" ]; then
		up_args+=(--force-recreate)
	fi

	info "Redeploying $name..."

	if ! compose_cmd "$dir" pull; then
		err "Failed to pull images for $name"
		return 1
	fi
	if ! compose_cmd "$dir" up "${up_args[@]}"; then
		err "Failed to redeploy $name"
		return 1
	fi

	ok "$name redeployed"
}

compose_stop_service() {
	local dir=$1 service=$2
	compose_cmd "$dir" stop "$service" 2>/dev/null || true
}

compose_down() {
	local dir=$1
	compose_cmd "$dir" down -v 2>/dev/null || true
}

deploy_core_services() {
	local stack name dir
	for stack in "${CORE_STACKS[@]}"; do
		IFS='|' read -r name dir <<<"$stack"
		deploy_compose "$dir" "$name"
	done
}

stop_core_services() {
	local i stack name dir
	for ((i = ${#CORE_STACKS[@]} - 1; i >= 0; i--)); do
		IFS='|' read -r name dir <<<"${CORE_STACKS[$i]}"
		compose_down "$dir"
	done
}

# Config
USER_HOME="/home/jaw"
SUDO="sudo"
REPO_DIR="$USER_HOME/home-ops"
DOCKER_CD_DIR="$REPO_DIR/apps/docker-cd"
TRAEFIK_DIR="$REPO_DIR/apps/traefik"
OAUTH2_PROXY_DIR="$REPO_DIR/apps/oauth2-proxy"
DOCKER_CD_SECRET_FILE="$DOCKER_CD_DIR/.env.sops"
DOCKER_CD_DATA_DIR="$USER_HOME/data/docker-cd"
export SOPS_AGE_KEY_FILE="$USER_HOME/.sops/age-key.txt"

# NFS config
NAS_IP="192.168.4.243"
NFS_MOUNTS=(
	"plex|/volume1/plex|$USER_HOME/plex"
	"backup|/volume1/backup|$USER_HOME/backup"
	"immich|/volume1/immich|$USER_HOME/immich"
)

# Static directories (not in compose files)
STATIC_DIRS=(
	"$DOCKER_CD_DATA_DIR"
	"$USER_HOME/data/dozzle"
	"$USER_HOME/plex/downloads"
	"$USER_HOME/plex/movies"
	"$USER_HOME/plex/tv"
	"$USER_HOME/plex/music"
	"$USER_HOME/plex/audiobooks"
	"$USER_HOME/plex/podcasts"
	"$USER_HOME/.sops"
	"$USER_HOME/.docker"
)

CORE_STACKS=(
	"traefik|$TRAEFIK_DIR"
	"oauth2-proxy|$OAUTH2_PROXY_DIR"
	"docker-cd|$DOCKER_CD_DIR"
)

ensure_external_networks() {
	# External networks/volumes used across stacks.
	docker_cmd network create traefik 2>/dev/null || true
	docker_cmd volume create traefik-logs 2>/dev/null || true
}

#=============================================================================
# SETUP - Create directories
#=============================================================================
cmd_setup() {
	header "Mounts"
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
	dirs=$(sed -n "s|.*- \($USER_HOME/[^:]*\):.*|\1|p" "$REPO_DIR"/apps/*/docker-compose.yml 2>/dev/null | sort -u)
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
		return 1
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
		printf '%s\n' "$entry" | $SUDO tee -a /etc/fstab >/dev/null
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
	local action=${1:-} target=${2:-all}
	local matched=0
	[ -z "$action" ] && {
		printf 'Usage: %s nfs {mount|unmount|persist|unpersist|status} [plex|backup|all]\n' "$0"
		exit 1
	}

	case "$action" in
		mount | unmount | umount | persist | unpersist | status) ;;
		*) die "unknown nfs action: $action" ;;
	esac

	for mount in "${NFS_MOUNTS[@]}"; do
		IFS='|' read -r name nas_path local_path <<<"$mount"
		if [[ "$target" == "all" || "$target" == "$name" ]]; then
			matched=1
			case "$action" in
				mount) nfs_mount "$name" "$nas_path" "$local_path" ;;
				unmount | umount) nfs_unmount "$name" "$nas_path" "$local_path" ;;
				persist) nfs_persist "$name" "$nas_path" "$local_path" ;;
				unpersist) nfs_unpersist "$name" "$nas_path" "$local_path" ;;
				status) nfs_status "$name" "$nas_path" "$local_path" ;;
			esac
		fi
	done

	if [ "$matched" -eq 0 ]; then
		die "unknown nfs target: $target"
	fi
}

#=============================================================================
# INSTALL - Deploy all services
#=============================================================================
cmd_install() {
	header "home-ops Install"

	# Prerequisites
	step "1/4" "Checking prerequisites..."
	require_cmd curl
	require_cmd git
	[ ! -f "$SOPS_AGE_KEY_FILE" ] && {
		err "Copy age key: scp ~/.sops/age-key.txt $(whoami)@$(hostname -I | awk '{print $1}'):$USER_HOME/.sops/"
		exit 1
	}
	[ ! -d "$REPO_DIR" ] && {
		err "Clone repo: git clone https://github.com/wajeht/home-ops.git $REPO_DIR"
		exit 1
	}

	# Install Docker
	step "2/4" "Docker..."
	if ! command -v docker &>/dev/null; then
		curl -fsSL https://get.docker.com | $SUDO sh
	fi
	if [ "$EUID" -ne 0 ]; then
		local current_user
		current_user=$(id -un)
		$SUDO usermod -aG docker "$current_user"
		dim "Added $current_user to docker group (re-login to take effect)"
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

	deploy_core_services

	header "Done"
	printf '\n'
	printf '%b\n' "${BOLD}Containers:${NC}"
	docker_cmd ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || true
	printf '\n'
	ok "docker-cd will auto-deploy remaining apps within 60s: ${CYAN}https://cd.jaw.dev${NC}"
}

reset_docker_cd_state() {
	info "Resetting docker-cd state/cache..."

	# Stop docker-cd first so it cannot rewrite state while files are removed.
	compose_stop_service "$DOCKER_CD_DIR" docker-cd

	$SUDO rm -f "$DOCKER_CD_DATA_DIR/state.json" "$DOCKER_CD_DATA_DIR/history.json"
	$SUDO rm -rf "$DOCKER_CD_DATA_DIR/wajeht"

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
	local reply=""
	docker_cmd info >/dev/null
	printf '%b\n' "${RED}This will remove ALL containers, networks, and prune images.${NC}"
	read -r -n 1 -p "Continue? [y/N] " reply
	printf '\n'
	[[ ! $reply =~ ^[Yy]$ ]] && exit 1

	# Stop core services first to prevent re-deployments.
	step "1/4" "Stopping core services..."
	stop_core_services

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
			compose_down "$dir"
		fi
	done
	cd "$USER_HOME"

	step "3/4" "Removing networks..."
	for _ in 1 2 3; do
		docker_cmd network prune -f 2>/dev/null || true
		docker_cmd network rm traefik 2>/dev/null || true
		sleep 2
	done

	step "4/4" "Pruning images..."
	docker_cmd image prune -af 2>/dev/null || true
	docker_cmd system prune -af 2>/dev/null || true

	header "Done"
	cmd_status
}

#=============================================================================
# STATUS - Show current status
#=============================================================================
cmd_status() {
	header "Status"
	printf '\n'
	printf '%b\n' "${BOLD}Containers:${NC}"
	docker_cmd ps --format "table {{.Names}}\t{{.Status}}" 2>/dev/null || dim "None"
	printf '\n'
	printf '%b\n' "${BOLD}NFS Mounts:${NC}"
	cmd_nfs status
	printf '\n'
	printf '%b\n' "${BOLD}Disk:${NC}"
	df -h "$USER_HOME/data" "$USER_HOME/plex" 2>/dev/null | tail -n +2 || true
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
# UPDATE - Force-recreate docker-cd (which manages all other services)
#=============================================================================
prepare_update() {
	require_cmd git
	require_cmd sops

	cd "$REPO_DIR"
	info "Pulling latest..."
	git pull

	# Keep submodules current after pull.
	sync_submodules || warn "Submodule sync failed, continuing"

	docker_relogin
	ensure_external_networks
}

cmd_update() {
	header "Force-updating docker-cd"
	prepare_update

	step "1/2" "Stopping docker-cd..."
	compose_stop_service "$DOCKER_CD_DIR" docker-cd

	step "2/2" "Force-redeploying docker-cd..."
	redeploy_compose "$DOCKER_CD_DIR" docker-cd 1

	header "Done"
}

#=============================================================================
# IMAGES - Show/remove unused Docker images and volumes
#=============================================================================
cmd_images() {
	local action=${1:-status}
	docker_cmd info >/dev/null
	header "Docker Cleanup"

	case "$action" in
		status)
			local running_file tmp_dir
			tmp_dir=$(mktemp -d)
			running_file="$tmp_dir/running-images"
			docker_cmd ps --format '{{.ID}}' | while read -r cid; do
				docker_cmd inspect --format '{{.Image}}' "$cid" 2>/dev/null | sed 's/sha256://' | cut -c1-12
			done | sort -u >"$running_file"

			printf '\n'
			printf '%b\n' "${BOLD}Stale images (outdated, freed after next redeploy):${NC}"
			local stale_out
			stale_out=$(docker_cmd images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' | awk -F'\t' '$3 == "<none>"' | while IFS=$'\t' read -r id repo _ size; do
				if grep -q "$id" "$running_file" 2>/dev/null; then
					printf "  %-45s %10s\n" "$repo" "$size"
				fi
			done)
			if [ -z "$stale_out" ]; then dim "None"; else printf '%s\n' "$stale_out"; fi

			printf '\n'
			printf '%b\n' "${BOLD}Prunable images (safe to remove now):${NC}"
			local prunable_out
			prunable_out=$(docker_cmd images --format '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}' | while IFS=$'\t' read -r id repo tag size; do
				grep -q "$id" "$running_file" 2>/dev/null || printf "  %-45s %10s\n" "$repo:$tag" "$size"
			done)
			if [ -z "$prunable_out" ]; then dim "None"; else printf '%s\n' "$prunable_out"; fi

			rm -rf "$tmp_dir"

			printf '\n'
			printf '%b\n' "${BOLD}Orphan volumes:${NC}"
			local total_vols orphan_vols
			total_vols=$(docker_cmd volume ls -q | wc -l)
			orphan_vols=$(docker_cmd volume ls -f dangling=true -q | wc -l)
			printf '  %s orphan (%s total)\n' "$orphan_vols" "$total_vols"

			printf '\n'
			printf '%b\n' "${BOLD}Docker disk usage:${NC}"
			docker_cmd system df

			printf '\n'
			dim "Stale images free up after docker-cd redeploys those stacks"
			dim "Run '$0 images prune' to remove prunable images and orphan volumes"
			;;
		prune)
			info "Removing unused images..."
			docker_cmd image prune -af
			printf '\n'
			info "Removing orphan volumes..."
			docker_cmd volume prune -f
			printf '\n'
			info "Final state:"
			docker_cmd system df
			ok "Cleanup complete"
			;;
		*)
			printf 'Usage: %s images [status|prune]\n' "$0"
			;;
	esac
}

#=============================================================================
# UPDATE-SUBMODULES - Update submodules to latest and commit
#=============================================================================
cmd_update_submodules() {
	header "Updating submodules"
	require_cmd git
	cd "$REPO_DIR"

	[ ! -f .gitmodules ] && {
		warn "No submodules found"
		return 0
	}

	local updated=0
	# shellcheck disable=SC2016
	git submodule foreach --quiet 'printf "%s\n" "$sm_path"' | while read -r sm_path; do
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
	printf '%b\n' "${BOLD}home-ops${NC} setup script"
	printf '\n'
	printf '%b\n' "Usage: ${CYAN}$0${NC} <command> [args]"
	printf '\n'
	printf '%b\n' "${BOLD}Commands:${NC}"
	printf '%b\n' "  ${GREEN}setup${NC}                    Create all data directories"
	printf '%b\n' "  ${GREEN}nfs mount${NC} [target]       Mount NFS shares (plex|backup|all)"
	printf '%b\n' "  ${GREEN}nfs unmount${NC} [target]     Unmount NFS shares"
	printf '%b\n' "  ${GREEN}nfs persist${NC} [target]     Add NFS mounts to fstab (survives reboot)"
	printf '%b\n' "  ${GREEN}nfs unpersist${NC} [target]   Remove NFS mounts from fstab"
	printf '%b\n' "  ${GREEN}nfs status${NC}               Show NFS mount status"
	printf '%b\n' "  ${GREEN}install${NC}                  Deploy all services"
	printf '%b\n' "  ${GREEN}install-fresh${NC}            Reset docker-cd state, then deploy all services"
	printf '%b\n' "  ${GREEN}uninstall${NC}                Remove all services and cleanup"
	printf '%b\n' "  ${GREEN}relogin${NC}                  Refresh docker registry credentials"
	printf '%b\n' "  ${GREEN}update${NC}                   Force-recreate docker-cd"
	printf '%b\n' "  ${GREEN}images${NC}                   Show unused Docker images and volumes"
	printf '%b\n' "  ${GREEN}images prune${NC}             Remove unused images and orphan volumes"
	printf '%b\n' "  ${GREEN}update-submodules${NC}        Update submodules to latest and commit"
	printf '%b\n' "  ${GREEN}status${NC}                   Show containers, mounts, disk usage"
	printf '\n'
	printf '%b\n' "${BOLD}Examples:${NC}"
	printf '%b\n' "  ${DIM}$0 setup${NC}                 # Create directories"
	printf '%b\n' "  ${DIM}$0 nfs mount${NC}             # Mount all NFS shares"
	printf '%b\n' "  ${DIM}$0 nfs mount plex${NC}        # Mount only plex"
	printf '%b\n' "  ${DIM}$0 install${NC}               # Deploy everything"
	printf '%b\n' "  ${DIM}$0 install-fresh${NC}         # Force full docker-cd app reconcile"
	printf '%b\n' "  ${DIM}$0 update${NC}                # Force-recreate docker-cd"
	printf '%b\n' "  ${DIM}$0 status${NC}                # Show status"
}

case "${1:-}" in
	"" | help | -h | --help)
		print_usage
		exit 0
		;;
	setup)
		cmd_setup
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
	update)
		cmd_update
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
