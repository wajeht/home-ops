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
shellcheck -x scripts/home-ops.sh scripts/lint.sh || fail=1

# SOPS encryption
echo "Checking SOPS encryption..."
while IFS= read -r -d '' f; do
	if ! grep -q 'sops_mac=' "$f"; then
		echo "ERROR: $f is not SOPS-encrypted"
		fail=1
	fi
done < <(find . -name '.env.sops' -not -path './.git/*' -not -path './apps/adguard/*' -print0)

# Container hardening
echo "Checking container hardening..."
while IFS= read -r -d '' f; do
	if ! grep -q 'cap_drop' "$f"; then
		echo "ERROR: $f missing cap_drop: [ALL]"
		fail=1
	fi
	if ! grep -q 'no-new-privileges' "$f"; then
		echo "ERROR: $f missing security_opt: no-new-privileges"
		fail=1
	fi
done < <(find apps -name 'docker-compose.yml' -print0)

# Compose syntax
echo "Checking compose files..."
while IFS= read -r -d '' f; do
	dir=$(dirname "$f")
	touch "$dir/.env"
	if ! docker compose -f "$f" config -q 2>/dev/null; then
		echo "ERROR: $f is invalid"
		fail=1
	fi
done < <(find . -name 'docker-compose.yml' -not -path './.git/*' -not -path './apps/adguard/*' -print0)

exit $fail
