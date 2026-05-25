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

total_cpus=0
total_memory_mb=0
errors=0

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
			echo "  WARN: unknown memory unit in $compose: $memory"
			continue
		fi

		# per-service checks
		if [ "$mem_mb" -gt "$MAX_SERVICE_MEMORY_MB" ]; then
			echo "FAIL: ${app}/${service} memory ${memory} exceeds per-service max $(awk "BEGIN {printf \"%.0f\", $MAX_SERVICE_MEMORY_MB / 1024}")G"
			errors=1
		fi

		if awk "BEGIN {exit !($cpus > $MAX_SERVICE_CPUS)}"; then
			echo "FAIL: ${app}/${service} cpus ${cpus} exceeds per-service max ${MAX_SERVICE_CPUS}"
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
max_total_memory_mb=$((MAX_MEMORY_MB * MAX_MEMORY_OVERCOMMIT))
max_total_memory_gb=$((MAX_MEMORY_MB / 1024 * MAX_MEMORY_OVERCOMMIT))
max_total_cpus=$(awk "BEGIN {printf \"%.1f\", $MAX_CPUS * $MAX_CPU_OVERCOMMIT}")
cpu_ratio=$(awk "BEGIN {printf \"%.1f\", $total_cpus / $MAX_CPUS}")
mem_ratio=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / $MAX_MEMORY_MB}")

echo "Resource limits summary (Dell OptiPlex 7050: ${MAX_CPUS} threads, $((MAX_MEMORY_MB / 1024))GB RAM)"
echo "  CPU:    ${total_cpus} / ${max_total_cpus} threads (${cpu_ratio}x overcommit, ${MAX_CPU_OVERCOMMIT}x limit)"
echo "  Memory: ${total_memory_gb}GB / ${max_total_memory_gb}GB max (${mem_ratio}x overcommit, ${MAX_MEMORY_OVERCOMMIT}x limit)"
echo "  Per-service max: $((MAX_SERVICE_MEMORY_MB / 1024))G memory, ${MAX_SERVICE_CPUS} cpus"

# total memory check
if [ "$total_memory_mb" -gt "$max_total_memory_mb" ]; then
	echo "FAIL: Total memory ${total_memory_gb}GB exceeds ${MAX_MEMORY_OVERCOMMIT}x overcommit limit (${max_total_memory_gb}GB)"
	errors=1
fi

# total cpu check
if awk "BEGIN {exit !($total_cpus > $max_total_cpus)}"; then
	echo "FAIL: Total CPU ${total_cpus} exceeds ${MAX_CPU_OVERCOMMIT}x overcommit limit (${max_total_cpus} threads)"
	errors=1
fi

if [ "$errors" -eq 0 ]; then
	echo "OK: within limits"
fi

exit "$errors"
