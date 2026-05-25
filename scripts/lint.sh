#!/usr/bin/env bash
set -euo pipefail

# TTY-aware colors — disabled when stdout isn't a terminal.
if [ -t 1 ]; then
	BOLD=$'\033[1m'
	DIM=$'\033[2m'
	RED=$'\033[31m'
	GREEN=$'\033[32m'
	CYAN=$'\033[36m'
	RESET=$'\033[0m'
else
	BOLD=''
	DIM=''
	RED=''
	GREEN=''
	CYAN=''
	RESET=''
fi

ok="${GREEN}✓${RESET}"
xx="${RED}✗${RESET}"

fail=0

# Run a check and emit ✓ on success; on failure, emit ✗ and indent the captured
# output beneath. Each check is a shell function defined below.
run_check() {
	local label="$1" fn="$2" output rc
	output=$("$fn" 2>&1) && rc=0 || rc=$?
	if [ "$rc" -eq 0 ]; then
		printf '  %s %s\n' "$ok" "$label"
	else
		printf '  %s %s\n' "$xx" "$label"
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			printf '      %s%s%s\n' "$DIM" "$line" "$RESET"
		done <<<"$output"
		fail=1
	fi
}

# shellcheck disable=SC2329
check_shell() {
	shellcheck -x scripts/home-ops.sh scripts/lint.sh scripts/check-resources.sh
}

# shellcheck disable=SC2329
check_sops() {
	local missing=() f
	while IFS= read -r -d '' f; do
		grep -q 'sops_mac=' "$f" || missing+=("$f")
	done < <(find . -name '.env.sops' -not -path './.git/*' -not -path './apps/adguard/*' -print0)
	if [ "${#missing[@]}" -gt 0 ]; then
		printf '%s not SOPS-encrypted\n' "${missing[@]}"
		return 1
	fi
}

# shellcheck disable=SC2329
check_hardening() {
	local missing=() f
	while IFS= read -r -d '' f; do
		grep -q 'cap_drop' "$f" || grep -q '# lint-ignore: cap_drop' "$f" || missing+=("$f: missing cap_drop")
		grep -q 'no-new-privileges' "$f" || grep -q '# lint-ignore: no-new-privileges' "$f" || missing+=("$f: missing no-new-privileges")
	done < <(find apps -name 'docker-compose.yml' -print0)
	if [ "${#missing[@]}" -gt 0 ]; then
		printf '%s\n' "${missing[@]}"
		return 1
	fi
}

# shellcheck disable=SC2329
check_compose() {
	local broken=() f dir
	while IFS= read -r -d '' f; do
		dir=$(dirname "$f")
		touch "$dir/.env"
		docker compose -f "$f" config -q 2>/dev/null || broken+=("$f invalid")
	done < <(find . -name 'docker-compose.yml' -not -path './.git/*' -not -path './apps/adguard/*' -print0)
	if [ "${#broken[@]}" -gt 0 ]; then
		printf '%s\n' "${broken[@]}"
		return 1
	fi
}

printf '\n%s==>%s %slint%s\n' "$BOLD$CYAN" "$RESET" "$BOLD" "$RESET"
run_check "shell scripts" check_shell
run_check "sops encryption" check_sops
run_check "container hardening" check_hardening
run_check "compose syntax" check_compose

if [ "$fail" -eq 0 ]; then
	printf '\n  %s✓%s all checks passed\n' "$GREEN" "$RESET"
else
	printf '\n  %s✗ lint failed%s\n' "$RED$BOLD" "$RESET"
fi

exit "$fail"
