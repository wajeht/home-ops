#!/usr/bin/env bash
# Shared helpers for scripts/*. Keep this small and boring.

# shellcheck disable=SC2034
SCRIPT_UTILS_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC2034
REPO_ROOT=$(cd -- "$SCRIPT_UTILS_DIR/.." && pwd)

scripts_setup_colors() {
	if [ -t 1 ]; then
		BOLD=$'\033[1m'
		DIM=$'\033[2m'
		RED=$'\033[31m'
		GREEN=$'\033[32m'
		YELLOW=$'\033[33m'
		BLUE=$'\033[34m'
		CYAN=$'\033[36m'
		RESET=$'\033[0m'
	else
		BOLD=''
		DIM=''
		RED=''
		GREEN=''
		YELLOW=''
		BLUE=''
		CYAN=''
		RESET=''
	fi
	NC="$RESET"
}

scripts_setup_colors

info() { printf '%b\n' "${BLUE}${BOLD}::${RESET} $*"; }
ok() { printf '%b\n' "${GREEN}${BOLD}ok${RESET} $*"; }
warn() { printf '%b\n' "${YELLOW}${BOLD}warn${RESET} $*"; }
err() { printf '%b\n' "${RED}${BOLD}err${RESET} $*" >&2; }
step() { printf '\n%b\n' "${CYAN}${BOLD}[$1]${RESET} $2"; }
header() { printf '\n%b\n' "${BOLD}=== $* ===${RESET}"; }
dim() { printf '%b\n' "${DIM}  $*${RESET}"; }

die() {
	err "$*"
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "$1 is required"
}

SCRIPT_TMP_DIRS=()

make_temp_dir() {
	local __result_var=${1:-}
	local __tmp_dir
	[ -n "$__result_var" ] || die "make_temp_dir requires a result variable name"
	__tmp_dir=$(mktemp -d)
	SCRIPT_TMP_DIRS+=("$__tmp_dir")
	printf -v "$__result_var" '%s' "$__tmp_dir"
}

cleanup_temp_dirs() {
	local tmp_dir
	for tmp_dir in "${SCRIPT_TMP_DIRS[@]-}"; do
		[ -n "$tmp_dir" ] || continue
		rm -rf "$tmp_dir"
	done
}

trap cleanup_temp_dirs EXIT
