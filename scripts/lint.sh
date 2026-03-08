#!/usr/bin/env bash
set -euo pipefail

fail=0

# Formatting
echo "Checking formatting..."
npx oxfmt --check "**/*.{yml,yaml,md,json}" '!apps/adguard/**' || fail=1

# Shell formatting
echo "Checking shell formatting..."
shfmt -d -i 0 -ci scripts/*.sh || fail=1

# Shellcheck
echo "Checking shell scripts..."
shellcheck -x scripts/home-ops.sh || fail=1

# SOPS encryption
echo "Checking SOPS encryption..."
for f in $(find . -name '.env.sops' -not -path './.git/*' -not -path './apps/adguard/*'); do
	if ! grep -q 'sops_mac=' "$f"; then
		echo "ERROR: $f is not SOPS-encrypted"
		fail=1
	fi
done

# Container hardening
echo "Checking container hardening..."
for f in $(find apps -name 'docker-compose.yml'); do
	if ! grep -q 'cap_drop' "$f"; then
		echo "ERROR: $f missing cap_drop: [ALL]"
		fail=1
	fi
	if ! grep -q 'no-new-privileges' "$f"; then
		echo "ERROR: $f missing security_opt: no-new-privileges"
		fail=1
	fi
done

# Compose syntax
echo "Checking compose files..."
tmp_env=$(mktemp)
trap 'rm -f "$tmp_env"' EXIT
for f in $(find . -name 'docker-compose.yml' -not -path './.git/*' -not -path './apps/adguard/*'); do
	if ! docker compose --env-file "$tmp_env" -f "$f" config -q 2>/dev/null; then
		echo "ERROR: $f is invalid"
		fail=1
	fi
done

exit $fail
