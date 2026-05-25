#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dynamic_file="$repo_dir/apps/traefik/dynamic.yml"
compose_file="$repo_dir/apps/traefik/docker-compose.yml"

usage() {
	cat <<'EOF'
Usage: scripts/update-cloudflare-ips.sh [options]

Fetch Cloudflare's published edge IP ranges and update Traefik's origin
allowlist/trusted-header ranges.

Options:
  -h, --help  Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		-h | --help)
			usage
			exit 0
			;;
		*)
			printf 'unknown option: %s\n' "$1" >&2
			usage >&2
			exit 2
			;;
	esac
done

if ! command -v jq >/dev/null 2>&1; then
	printf 'jq is required\n' >&2
	exit 1
fi

for file in "$dynamic_file" "$compose_file"; do
	if [ ! -f "$file" ]; then
		printf 'missing file: %s\n' "$file" >&2
		exit 1
	fi
done

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

ranges_file="$tmp_dir/cloudflare-ranges.txt"

curl -fsSL https://api.cloudflare.com/client/v4/ips |
	jq -r '.result.ipv4_cidrs[], .result.ipv6_cidrs[]' >"$ranges_file"

if [ ! -s "$ranges_file" ]; then
	printf 'Cloudflare API returned no IP ranges\n' >&2
	exit 1
fi

cp "$dynamic_file" "$tmp_dir/dynamic.yml.before"
cp "$compose_file" "$tmp_dir/docker-compose.yml.before"

replace_block() {
	local file="$1" start="$2" end="$3" body="$4" tmp
	tmp=$(mktemp)
	awk -v start="$start" -v end="$end" -v body="$body" '
		index($0, start) {
			found = 1
			print
			while ((getline line < body) > 0) print line
			close(body)
			skip = 1
			next
		}
		index($0, end) {
			end_found = 1
			skip = 0
			print
			next
		}
		!skip { print }
		END {
			if (!found) exit 42
			if (!end_found) exit 43
		}
	' "$file" >"$tmp"
	mv "$tmp" "$file"
}

source_body="$tmp_dir/source-ranges.yml"
compose_body="$tmp_dir/compose-trusted-ranges.yml"

sed 's/^/          - /' "$ranges_file" >"$source_body"

trusted_ips=$(paste -sd, "$ranges_file")
{
	printf '      - "--entrypoints.websecure.forwardedHeaders.trustedIPs=%s"\n' "$trusted_ips"
	printf '      - "--entrypoints.web.forwardedHeaders.trustedIPs=%s"\n' "$trusted_ips"
} >"$compose_body"

replace_block "$dynamic_file" "BEGIN managed cloudflare source ranges" "END managed cloudflare source ranges" "$source_body"
replace_block "$compose_file" "BEGIN managed Cloudflare trusted IPs" "END managed Cloudflare trusted IPs" "$compose_body"

changed=0
if ! cmp -s "$dynamic_file" "$tmp_dir/dynamic.yml.before"; then
	changed=1
fi
if ! cmp -s "$compose_file" "$tmp_dir/docker-compose.yml.before"; then
	changed=1
fi

if [ "$changed" -eq 0 ]; then
	printf 'Cloudflare IP ranges already current\n'
	exit 0
fi

printf 'updated Cloudflare IP ranges in Traefik config\n'
