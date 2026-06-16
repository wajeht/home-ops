#!/usr/bin/env bash
# shellcheck disable=SC2317,SC2329  # check_* functions are dispatched indirectly via run_check
set -euo pipefail

# shellcheck source=scripts/utils.sh
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/utils.sh"
cd "$REPO_ROOT"

ok_mark="${GREEN}✓${RESET}"
fail_mark="${RED}✗${RESET}"

fail=0

# Run a check and emit ✓ on success; on failure, emit ✗ and indent the captured
# output beneath. Each check is a shell function defined below.
run_check() {
	local label="$1" fn="$2" output rc
	output=$("$fn" 2>&1) && rc=0 || rc=$?
	if [ "$rc" -eq 0 ]; then
		printf '  %s %s\n' "$ok_mark" "$label"
		if [ -n "$output" ]; then
			while IFS= read -r line; do
				[ -z "$line" ] && continue
				printf '      %s%s%s\n' "$DIM" "$line" "$RESET"
			done <<<"$output"
		fi
	else
		printf '  %s %s\n' "$fail_mark" "$label"
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			printf '      %s%s%s\n' "$DIM" "$line" "$RESET"
		done <<<"$output"
		fail=1
	fi
}

# shellcheck disable=SC2329
check_shell() {
	find scripts apps -name '*.sh' -print0 |
		xargs -0 shellcheck -x
}

# shellcheck disable=SC2329
check_sops() {
	local missing=() f
	while IFS= read -r -d '' f; do
		grep -q 'sops_mac=' "$f" || missing+=("$f")
	done < <(find . -name '.env.sops' -not -path './.git/*' -print0)
	if [ "${#missing[@]}" -gt 0 ]; then
		printf '%s not SOPS-encrypted\n' "${missing[@]}"
		return 1
	fi
}

# shellcheck disable=SC2329
check_docker_cd_app_config() {
	local legacy=() f
	while IFS= read -r -d '' f; do
		legacy+=("$f: move app config to top-level x-docker-cd in docker-compose.yml")
	done < <(find apps -mindepth 2 -maxdepth 2 -name 'docker-cd.yml' -print0)
	if [ "${#legacy[@]}" -gt 0 ]; then
		printf '%s\n' "${legacy[@]}"
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
	local broken=() f dir had_env
	while IFS= read -r -d '' f; do
		dir=$(dirname "$f")
		had_env=0
		if [ -f "$dir/.env" ]; then
			had_env=1
		else
			: >"$dir/.env"
		fi

		docker compose -f "$f" --project-directory "$dir" config -q 2>/dev/null || broken+=("$f invalid")

		if [ "$had_env" -eq 0 ]; then
			rm -f "$dir/.env"
		fi
	done < <(find . -name 'docker-compose.yml' -not -path './.git/*' -print0)
	if [ "${#broken[@]}" -gt 0 ]; then
		printf '%s\n' "${broken[@]}"
		return 1
	fi
}

# Per-service hygiene check — every service must have logging, restart, init, healthcheck.
# `init` and `healthcheck` accept a file-level `# lint-ignore: <key>` escape (LSIO/s6 images,
# scratch images with no shell, etc.). logging and restart are non-negotiable.
# shellcheck disable=SC2329
check_service_hygiene() {
	local issues=() f
	while IFS= read -r -d '' f; do
		while IFS= read -r line; do
			[ -z "$line" ] && continue
			issues+=("$f $line")
		done < <(awk '
			function flush() {
				if (!svc) return
				if (!has_logging)     print svc " missing logging"
				if (!has_restart)     print svc " missing restart"
				if (!has_init && !ignore_init)               print svc " missing init"
				if (!has_healthcheck && !ignore_healthcheck) print svc " missing healthcheck"
			}
			/# lint-ignore: init/        { ignore_init=1 }
			/# lint-ignore: healthcheck/ { ignore_healthcheck=1 }
			/^services:[[:space:]]*$/ { in_svcs=1; next }
			/^[a-zA-Z]/ && in_svcs    { flush(); in_svcs=0; svc="" }
			in_svcs && /^  [a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
				flush()
				svc=$0; sub(/^  /, "", svc); sub(/:.*/, "", svc)
				has_logging=0; has_restart=0; has_init=0; has_healthcheck=0
			}
			svc && /^    logging:/     { has_logging=1 }
			svc && /^    restart:/     { has_restart=1 }
			svc && /^    init:/        { has_init=1 }
			svc && /^    healthcheck:/ { has_healthcheck=1 }
			END { flush() }
		' "$f")
	done < <(find apps -name 'docker-compose.yml' -print0)
	if [ "${#issues[@]}" -gt 0 ]; then
		printf '%s\n' "${issues[@]}"
		return 1
	fi
}

# Every app that bind-mounts /home/jaw/data/<app>/ should have a backrest plan with id=<app>.
# The catch-all `global` plan covers everything under ~/data, but per-app plans give
# isolated repos + per-app retention/hooks (SQLite .backup, pg_dump, etc.).
# shellcheck disable=SC2329
check_backup() {
	local missing=() app f plans
	plans=$(jq -r '.plans[].id' apps/backrest/config/config.json 2>/dev/null) || return 1
	for f in apps/*/docker-compose.yml; do
		app=$(basename "$(dirname "$f")")
		[ "$app" = "backrest" ] && continue
		grep -q '# lint-ignore: backup' "$f" && continue
		grep -qE "^[[:space:]]+-[[:space:]]+/home/jaw/data/${app}[/:]" "$f" || continue
		grep -qx "$app" <<<"$plans" || missing+=("$f: /home/jaw/data/$app mounted but no backrest plan id=$app")
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		printf '%s\n' "${missing[@]}"
		return 1
	fi
}

resource_bar() {
	local ratio="$1" limit="$2" bar_width=20
	local pct filled empty color i
	pct=$(awk "BEGIN {p = $ratio / $limit * 100; if (p > 100) p = 100; printf \"%d\", p}")
	filled=$((pct * bar_width / 100))
	empty=$((bar_width - filled))
	if [ "$pct" -ge 80 ]; then
		color="$RED"
	elif [ "$pct" -ge 60 ]; then
		color="$YELLOW"
	else
		color="$GREEN"
	fi

	printf '%s' "$color"
	for ((i = 0; i < filled; i++)); do printf '█'; done
	printf '%s' "$DIM"
	for ((i = 0; i < empty; i++)); do printf '░'; done
	printf '%s' "$RESET"
}

# shellcheck disable=SC2329
check_resources() {
	local max_cpus=8
	local max_memory_mb=32768
	local max_memory_overcommit=3
	local max_cpu_overcommit=15
	local max_service_memory_mb=8192
	local max_service_cpus="4.0"
	local total_cpus=0
	local total_memory_mb=0
	local errors=0
	local compose app limited_services cpus memory service mem_mb svc shm stop oom
	local total_memory_gb max_total_memory_gb max_total_memory_mb max_total_cpus
	local cpu_ratio mem_ratio host_ram_gb cpu_bar mem_bar
	local issues=()
	local warnings=()

	for compose in apps/*/docker-compose.yml; do
		app="$(basename "$(dirname "$compose")")"
		limited_services=" "

		while read -r cpus memory service; do
			if [[ "$memory" == *G ]]; then
				mem_mb=$(awk "BEGIN {printf \"%.0f\", ${memory%G} * 1024}")
			elif [[ "$memory" == *M ]]; then
				mem_mb="${memory%M}"
			else
				issues+=("${app}/${service} unknown memory unit: ${memory}")
				errors=1
				continue
			fi

			if [ "$mem_mb" -gt "$max_service_memory_mb" ]; then
				issues+=("${app}/${service} memory ${memory} exceeds per-service max $(awk "BEGIN {printf \"%.0f\", $max_service_memory_mb / 1024}")G")
				errors=1
			fi

			if awk "BEGIN {exit !($cpus > $max_service_cpus)}"; then
				issues+=("${app}/${service} cpus ${cpus} exceeds per-service max ${max_service_cpus}")
				errors=1
			fi

			total_cpus=$(awk "BEGIN {printf \"%.1f\", $total_cpus + $cpus}")
			total_memory_mb=$((total_memory_mb + mem_mb))
			limited_services+="${service} "
		done < <(awk '
			/^  [a-zA-Z]/ && /:/ && !/deploy:/ && !/resources:/ && !/limits:/ && !/cpus:/ && !/memory:/ && !/labels:/ && !/reservations:/ { gsub(/:.*/, ""); gsub(/^ +/, ""); svc=$0 }
			/deploy:/ { in_deploy=1; next }
			in_deploy && /resources:/ { in_resources=1; next }
			in_deploy && in_resources && /limits:/ { in_limits=1; next }
			in_limits && /cpus:/ { gsub(/[" ]/, "", $2); cpus=$2; next }
			in_limits && /memory:/ { gsub(/[" ]/, "", $2); mem=$2 }
			in_limits && cpus && mem { print cpus, mem, svc; cpus=""; mem=""; in_deploy=0; in_resources=0; in_limits=0 }
			/^[^ ]/ || /^  [^ ]/ { if (in_deploy && !/deploy:/) { in_deploy=0; in_resources=0; in_limits=0; cpus=""; mem="" } }
		' "$compose")

		while IFS= read -r svc; do
			[ -z "$svc" ] && continue
			case "$limited_services" in
				*" $svc "*) ;;
				*)
					issues+=("${app}/${svc} missing deploy.resources.limits")
					errors=1
					;;
			esac
		done < <(awk '
			/^services:[[:space:]]*$/ { in_svcs=1; next }
			/^[a-zA-Z]/ && in_svcs { in_svcs=0 }
			in_svcs && /^  [a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
				name = $0; sub(/^  /, "", name); sub(/:.*/, "", name); print name
			}
		' "$compose")

		while read -r svc shm stop oom; do
			[ "$shm" = "-" ] && warnings+=("${app}/${svc} postgres missing shm_size (recommended: 256m)")
			[ "$stop" = "-" ] && warnings+=("${app}/${svc} postgres missing stop_grace_period (recommended: 30s)")
			[ "$oom" = "-" ] && warnings+=("${app}/${svc} postgres missing oom_score_adj (recommended: -300)")
		done < <(awk '
			function flush() {
				if (svc && img ~ /(^|\/)postgres:/) {
					printf "%s %s %s %s\n", svc, (shm ? shm : "-"), (stop ? stop : "-"), (oom ? oom : "-")
				}
			}
			/^services:[[:space:]]*$/ { in_svcs=1; next }
			/^[a-zA-Z]/ && in_svcs { flush(); in_svcs=0; svc="" }
			in_svcs && /^  [a-zA-Z][a-zA-Z0-9_-]*:[[:space:]]*$/ {
				flush()
				svc=$0; sub(/^  /, "", svc); sub(/:.*/, "", svc)
				img=""; shm=""; stop=""; oom=""
			}
			svc && /^    image:[[:space:]]+/ {
				img=$0; sub(/^    image:[[:space:]]+/, "", img); gsub(/["'\'']/, "", img)
			}
			svc && /^    shm_size:/ { shm=$2 }
			svc && /^    stop_grace_period:/ { stop=$2 }
			svc && /^    oom_score_adj:/ { oom=$2 }
			END { flush() }
		' "$compose")
	done

	total_memory_gb=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / 1024}")
	max_total_memory_gb=$(awk "BEGIN {printf \"%.1f\", $max_memory_mb * $max_memory_overcommit / 1024}")
	max_total_memory_mb=$((max_memory_mb * max_memory_overcommit))
	max_total_cpus=$(awk "BEGIN {printf \"%.1f\", $max_cpus * $max_cpu_overcommit}")
	cpu_ratio=$(awk "BEGIN {printf \"%.1f\", $total_cpus / $max_cpus}")
	mem_ratio=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / $max_memory_mb}")
	host_ram_gb=$((max_memory_mb / 1024))
	cpu_bar=$(resource_bar "$cpu_ratio" "$max_cpu_overcommit")
	mem_bar=$(resource_bar "$mem_ratio" "$max_memory_overcommit")

	if [ "$total_memory_mb" -gt "$max_total_memory_mb" ]; then
		issues+=("total memory ${total_memory_gb}GB exceeds ${max_memory_overcommit}x overcommit limit (${max_total_memory_gb}GB)")
		errors=1
	fi
	if awk "BEGIN {exit !($total_cpus > $max_total_cpus)}"; then
		issues+=("total CPU ${total_cpus} exceeds ${max_cpu_overcommit}x overcommit limit (${max_total_cpus} threads)")
		errors=1
	fi

	printf '%sDell OptiPlex 7050 · %s threads · %sGB RAM%s\n' "$DIM" "$max_cpus" "$host_ram_gb" "$RESET"
	printf '%-7s %s%5s%s / %5s threads   %b  %s%sx of %sx%s\n' \
		"cpu" "$BOLD" "$total_cpus" "$RESET" "$max_total_cpus" "$cpu_bar" "$BOLD" "$cpu_ratio" "$max_cpu_overcommit" "$RESET"
	printf '%-7s %s%5s%s / %5s GB        %b  %s%sx of %sx%s\n' \
		"memory" "$BOLD" "$total_memory_gb" "$RESET" "$max_total_memory_gb" "$mem_bar" "$BOLD" "$mem_ratio" "$max_memory_overcommit" "$RESET"
	printf '%s%-7s%s %smax %sG mem · %s cpu per service%s\n' \
		"" "per-svc" "" "$DIM" "$((max_service_memory_mb / 1024))" "$max_service_cpus" "$RESET"

	if [ "${#warnings[@]}" -gt 0 ]; then
		printf 'resource warnings:\n'
		printf '%s\n' "${warnings[@]}"
	fi
	if [ "${#issues[@]}" -gt 0 ]; then
		printf '%s\n' "${issues[@]}"
	fi

	return "$errors"
}

printf '\n%s==>%s %slint%s\n' "$BOLD$CYAN" "$RESET" "$BOLD" "$RESET"
run_check "shell scripts" check_shell
run_check "sops encryption" check_sops
run_check "docker-cd app config" check_docker_cd_app_config
run_check "container hardening" check_hardening
run_check "service hygiene" check_service_hygiene
run_check "backup plans" check_backup
run_check "compose syntax" check_compose
run_check "resource limits" check_resources

if [ "$fail" -eq 0 ]; then
	printf '\n  %s✓%s all checks passed\n' "$GREEN" "$RESET"
else
	printf '\n  %s✗ lint failed%s\n' "$RED$BOLD" "$RESET"
fi

exit "$fail"
