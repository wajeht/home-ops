#!/usr/bin/env bash
# Report total resource limits across all compose files.
# Dell OptiPlex 7050: i7-7700 (4c/8t), 32GB RAM.

set -euo pipefail

MAX_CPUS=8
MAX_MEMORY_MB=32768

total_cpus=0
total_memory_mb=0

for compose in apps/*/docker-compose.yml; do
	while IFS= read -r line; do
		cpus=$(echo "$line" | awk '{print $1}')
		memory=$(echo "$line" | awk '{print $2}')

		if [[ "$memory" == *G ]]; then
			mem_mb=$(awk "BEGIN {printf \"%.0f\", ${memory%G} * 1024}")
		elif [[ "$memory" == *M ]]; then
			mem_mb="${memory%M}"
		else
			echo "  WARN: unknown memory unit in $compose: $memory"
			continue
		fi

		total_cpus=$(awk "BEGIN {printf \"%.1f\", $total_cpus + $cpus}")
		total_memory_mb=$((total_memory_mb + mem_mb))
	done < <(awk '
		/deploy:/ { in_deploy=1; next }
		in_deploy && /resources:/ { in_resources=1; next }
		in_deploy && in_resources && /limits:/ { in_limits=1; next }
		in_limits && /cpus:/ { gsub(/[" ]/, "", $2); cpus=$2; next }
		in_limits && /memory:/ { gsub(/[" ]/, "", $2); mem=$2 }
		in_limits && cpus && mem { print cpus, mem; cpus=""; mem=""; in_deploy=0; in_resources=0; in_limits=0 }
		/^[^ ]/ || /^  [^ ]/ { if (in_deploy && !/deploy:/) { in_deploy=0; in_resources=0; in_limits=0; cpus=""; mem="" } }
	' "$compose")
done

total_memory_gb=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / 1024}")
cpu_ratio=$(awk "BEGIN {printf \"%.1f\", $total_cpus / $MAX_CPUS}")
mem_ratio=$(awk "BEGIN {printf \"%.1f\", $total_memory_mb / $MAX_MEMORY_MB}")

echo "Resource limits summary (Dell OptiPlex 7050: ${MAX_CPUS} threads, $((MAX_MEMORY_MB / 1024))GB RAM)"
echo "  CPU:    ${total_cpus} / ${MAX_CPUS} threads (${cpu_ratio}x overcommit)"
echo "  Memory: ${total_memory_gb}GB / $((MAX_MEMORY_MB / 1024))GB (${mem_ratio}x overcommit)"
