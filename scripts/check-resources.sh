#!/usr/bin/env bash
# Check resource limits across all compose files.
# Dell OptiPlex 7050: i7-7700 (4c/8t), 32GB RAM.

set -euo pipefail

MAX_CPUS=8
MAX_MEMORY_MB=32768
MAX_MEMORY_OVERCOMMIT=3
# CPU overcommit is safer than memory (CFS throttles, no OOM-kill). Homelab norm is
# 5-10x against threads for mostly-idle workloads; VMware's "painful" zone starts at 6x
# for *active* VMs. 15x is the hard cap — well into territory where simultaneous bursts
# would queue noticeably even for idle services.
MAX_CPU_OVERCOMMIT=15
MAX_SERVICE_MEMORY_MB=8192
MAX_SERVICE_CPUS="4.0"
BAR_WIDTH=20

# TTY-aware colors — disabled when stdout isn't a terminal.
if [ -t 1 ]; then
	BOLD=$'\033[1m'
	DIM=$'\033[2m'
	RED=$'\033[31m'
	GREEN=$'\033[32m'
	YELLOW=$'\033[33m'
	CYAN=$'\033[36m'
	RESET=$'\033[0m'
else
	BOLD=''
	DIM=''
	RED=''
	GREEN=''
	YELLOW=''
	CYAN=''
	RESET=''
fi

total_cpus=0
total_memory_mb=0
errors=0
violations=()

for compose in apps/*/docker-compose.yml; do
	app="$(basename "$(dirname "$compose")")"

	while IFS= read -r line; do
		cpus=$(echo "$line" | awk '{print $1}')
		memory=$(echo "$line" | awk '{print $2}')
		service=$(echo "$line" | awk '{print $3}')

		if [[ "$memory" == *G ]]; then
			mem_mb=$(awk "BEGIN {printf \"%.0f\", ${memory%G} * 1024}")
		elif [[ "$memory" == *M ]]; then
			mem_mb="${memory%M}"
		else
			violations+=("${YELLOW}!${RESET}  ${app}/${service} unknown memory unit: ${memory}")
			continue
		fi

		if [ "$mem_mb" -gt "$MAX_SERVICE_MEMORY_MB" ]; then
			violations+=("${RED}✗${RESET}  ${app}/${service} memory ${memory} exceeds per-service max $(awk "BEGIN {printf \"%.0f\", $MAX_SERVICE_MEMORY_MB / 1024}")G")
			errors=1
		fi

		if awk "BEGIN {exit !($cpus > $MAX_SERVICE_CPUS)}"; then
			violations+=("${RED}✗${RESET}  ${app}/${service} cpus ${cpus} exceeds per-service max ${MAX_SERVICE_CPUS}")
			errors=1
		fi

		total_cpus=$(awk "BEGIN {printf \"%.1f\", $total_cpus + $cpus}")
		total_memory_mb=$((total_memory_mb + mem_mb))
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
done

total_memory_gb=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / 1024}")
max_total_memory_gb=$(awk "BEGIN {printf \"%.1f\", $MAX_MEMORY_MB * $MAX_MEMORY_OVERCOMMIT / 1024}")
max_total_memory_mb=$((MAX_MEMORY_MB * MAX_MEMORY_OVERCOMMIT))
max_total_cpus=$(awk "BEGIN {printf \"%.1f\", $MAX_CPUS * $MAX_CPU_OVERCOMMIT}")
cpu_ratio=$(awk "BEGIN {printf \"%.1f\", $total_cpus / $MAX_CPUS}")
mem_ratio=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / $MAX_MEMORY_MB}")
host_ram_gb=$((MAX_MEMORY_MB / 1024))

# Overcommit check — fails if exceeding the limit.
if [ "$total_memory_mb" -gt "$max_total_memory_mb" ]; then
	violations+=("${RED}✗${RESET}  total memory ${total_memory_gb}GB exceeds ${MAX_MEMORY_OVERCOMMIT}x overcommit limit (${max_total_memory_gb}GB)")
	errors=1
fi
if awk "BEGIN {exit !($total_cpus > $max_total_cpus)}"; then
	violations+=("${RED}✗${RESET}  total CPU ${total_cpus} exceeds ${MAX_CPU_OVERCOMMIT}x overcommit limit (${max_total_cpus} threads)")
	errors=1
fi

# Render a green/yellow/red horizontal bar; coloring follows utilization-of-limit.
make_bar() {
	local ratio="$1" limit="$2"
	local pct filled empty color
	pct=$(awk "BEGIN {p = $ratio / $limit * 100; if (p > 100) p = 100; printf \"%d\", p}")
	filled=$((pct * BAR_WIDTH / 100))
	empty=$((BAR_WIDTH - filled))
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

cpu_bar=$(make_bar "$cpu_ratio" "$MAX_CPU_OVERCOMMIT")
mem_bar=$(make_bar "$mem_ratio" "$MAX_MEMORY_OVERCOMMIT")

# Output
printf '\n%s==>%s %sresources%s\n' "$BOLD$CYAN" "$RESET" "$BOLD" "$RESET"
printf '  %sDell OptiPlex 7050  ·  %s threads  ·  %sGB RAM%s\n\n' \
	"$DIM" "$MAX_CPUS" "$host_ram_gb" "$RESET"

# Aligned rows: label(7) value(20) bar(20) ratio
printf '  %-7s %s%5s%s / %5s threads   %b  %s%sx of %sx%s\n' \
	"cpu" "$BOLD" "$total_cpus" "$RESET" "$max_total_cpus" "$cpu_bar" "$BOLD" "$cpu_ratio" "$MAX_CPU_OVERCOMMIT" "$RESET"
printf '  %-7s %s%5s%s / %5s GB        %b  %s%sx of %sx%s\n' \
	"memory" "$BOLD" "$total_memory_gb" "$RESET" "$max_total_memory_gb" "$mem_bar" "$BOLD" "$mem_ratio" "$MAX_MEMORY_OVERCOMMIT" "$RESET"
printf '  %s%-7s%s %smax %sG mem · %s cpu per service%s\n' \
	"" "per-svc" "" "$DIM" "$((MAX_SERVICE_MEMORY_MB / 1024))" "$MAX_SERVICE_CPUS" "$RESET"

if [ "${#violations[@]}" -gt 0 ]; then
	printf '\n'
	for v in "${violations[@]}"; do printf '  %s\n' "$v"; done
fi

if [ "$errors" -eq 0 ]; then
	printf '\n  %s✓%s within limits\n' "$GREEN" "$RESET"
else
	printf '\n  %s✗ limit violations%s\n' "$RED$BOLD" "$RESET"
fi

exit "$errors"
