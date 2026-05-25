#!/usr/bin/env bash
# shellcheck disable=SC2029  # remote commands are intentionally built locally
set -euo pipefail

repo_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
whitelist_file="$repo_dir/apps/crowdsec/custom-whitelists.yaml"
remote_host=""
commit=0
push=0
unban=1
manual_ipv6_cidr="${CROWDSEC_WHITELIST_IPV6_CIDR:-}"

usage() {
	cat <<'EOF'
Usage: scripts/update-crowdsec-whitelist.sh [options]

Options:
  --server HOST       Fetch public IPs and unban through this host.
  --file PATH         Whitelist YAML to update.
  --ipv6-cidr CIDR    Force an IPv6 CIDR, for example 2600:1700:abcd:1234::/64.
  --commit            Commit the whitelist update if it changed.
  --push              Push the commit after --commit.
  --no-unban          Do not delete active decisions for detected IPs.
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--server | --ssh)
			remote_host="${2:?missing host for $1}"
			shift 2
			;;
		--file)
			whitelist_file="${2:?missing path for --file}"
			shift 2
			;;
		--ipv6-cidr)
			manual_ipv6_cidr="${2:?missing CIDR for --ipv6-cidr}"
			shift 2
			;;
		--commit)
			commit=1
			shift
			;;
		--push)
			push=1
			shift
			;;
		--no-unban)
			unban=0
			shift
			;;
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

if [ ! -f "$whitelist_file" ]; then
	printf 'missing whitelist file: %s\n' "$whitelist_file" >&2
	exit 1
fi

run_net() {
	local version="$1"
	local script
	script=$(
		cat <<EOF
set -e
curl -${version} -fsS --max-time 10 https://ifconfig.me ||
curl -${version} -fsS --max-time 10 https://api${version}.ipify.org ||
curl -${version} -fsS --max-time 10 https://icanhazip.com
EOF
	)

	if [ -n "$remote_host" ]; then
		ssh "$remote_host" "$script" 2>/dev/null || true
	else
		sh -c "$script" 2>/dev/null || true
	fi
}

trim_ip() {
	tr -d '\r' | awk 'NF { print $1; exit }'
}

public_ipv4=$(run_net 4 | trim_ip)
public_ipv6=$(run_net 6 | trim_ip)

if ! [[ "$public_ipv4" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
	printf 'could not detect public IPv4\n' >&2
	exit 1
fi

ipv6_cidr="$manual_ipv6_cidr"
if [ -z "$ipv6_cidr" ] && [[ "$public_ipv6" == *:* ]]; then
	ipv6_cidr=$(
		python3 - "$public_ipv6" <<'PY' 2>/dev/null || true
import ipaddress
import sys

print(ipaddress.ip_interface(sys.argv[1] + "/64").network)
PY
	)
fi

replace_block() {
	local start="$1" end="$2" content="$3" file="$4" tmp content_file
	tmp=$(mktemp)
	content_file=$(mktemp)
	printf '%s\n' "$content" >"$content_file"
	awk -v start="$start" -v end="$end" -v content_file="$content_file" '
		index($0, start) {
			print
			while ((getline line < content_file) > 0) print line
			close(content_file)
			skip = 1
			next
		}
		index($0, end) {
			skip = 0
			print
			next
		}
		!skip { print }
	' "$file" >"$tmp"
	mv "$tmp" "$file"
	rm -f "$content_file"
}

ipv4_block=$(
	cat <<EOF
    # AT&T residential — dynamic IP, update if it changes. Without this, google-auth
    # login redirects (401/403) on protected apps + CrowdSec bouncer responses get
    # mistaken for brute force and self-perpetuate a ban loop.
    - $public_ipv4
EOF
)

if [ -n "$ipv6_cidr" ]; then
	ipv6_block="    - $ipv6_cidr"
else
	ipv6_block=$(
		cat <<'EOF'
    # No stable home IPv6 prefix detected yet. If one appears, the updater will
    # add the /64 here instead of whitelisting one temporary IPv6 address.
EOF
	)
fi

before=$(mktemp)
cp "$whitelist_file" "$before"

replace_block "BEGIN managed public IPv4" "END managed public IPv4" "$ipv4_block" "$whitelist_file"
replace_block "BEGIN managed public IPv6" "END managed public IPv6" "$ipv6_block" "$whitelist_file"

changed=0
if ! cmp -s "$before" "$whitelist_file"; then
	changed=1
fi
rm -f "$before"

if [ "$unban" -eq 1 ]; then
	delete_cmd="docker exec crowdsec cscli decisions delete --ip '$public_ipv4' >/dev/null 2>&1 || true"
	if [ -n "$public_ipv6" ] && [[ "$public_ipv6" == *:* ]]; then
		delete_cmd="$delete_cmd; docker exec crowdsec cscli decisions delete --ip '$public_ipv6' >/dev/null 2>&1 || true"
	fi
	if [ -n "$remote_host" ]; then
		ssh "$remote_host" "$delete_cmd"
	else
		sh -c "$delete_cmd"
	fi
fi

if [ "$changed" -eq 0 ]; then
	printf 'whitelist already current: IPv4=%s' "$public_ipv4"
	[ -n "$ipv6_cidr" ] && printf ' IPv6=%s' "$ipv6_cidr"
	printf '\n'
	exit 0
fi

printf 'updated %s: IPv4=%s' "$whitelist_file" "$public_ipv4"
[ -n "$ipv6_cidr" ] && printf ' IPv6=%s' "$ipv6_cidr"
printf '\n'

if [ "$commit" -eq 1 ]; then
	git -C "$repo_dir" add "$whitelist_file"
	git -C "$repo_dir" commit -m "fix(crowdsec): update trusted public ips"
fi

if [ "$push" -eq 1 ]; then
	if [ "$commit" -ne 1 ]; then
		printf '--push requires --commit\n' >&2
		exit 2
	fi
	git -C "$repo_dir" push origin HEAD
fi
