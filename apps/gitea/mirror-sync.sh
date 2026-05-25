#!/usr/bin/env bash
# Sync all GitHub repos to Gitea as mirrors
# Runs as Docker service via docker-compose

set -euo pipefail

# Config from env
GITEA_URL="${GITEA_URL:-https://gitea.jaw.dev}"
GITHUB_USER="${GITHUB_USER:-wajeht}"

if [ -z "${GITEA_TOKEN:-}" ] || [ -z "${GH_TOKEN:-}" ]; then
	echo "Error: GITEA_TOKEN and GH_TOKEN env vars required"
	exit 1
fi

# Get all GitHub repos (paginated)
echo "Fetching GitHub repos for $GITHUB_USER..."
GITHUB_REPOS=""
page=1
while true; do
	repos=$(curl -fsS -H "Authorization: token $GH_TOKEN" \
		"https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner" | jq -r '.[].name // empty')
	[ -z "$repos" ] && break
	GITHUB_REPOS="$GITHUB_REPOS $repos"
	page=$((page + 1))
done

# Get existing Gitea repos (paginated)
echo "Fetching existing Gitea repos..."
GITEA_REPOS=""
page=1
while true; do
	repos=$(curl -fsS -H "Authorization: token $GITEA_TOKEN" \
		"$GITEA_URL/api/v1/user/repos?limit=100&page=$page" | jq -r '.[].name // empty')
	[ -z "$repos" ] && break
	GITEA_REPOS="$GITEA_REPOS
$repos"
	page=$((page + 1))
done

# Create mirrors for missing repos
created=0
skipped=0
for repo in $GITHUB_REPOS; do
	if echo "$GITEA_REPOS" | grep -qx "$repo"; then
		skipped=$((skipped + 1))
	else
		echo "-> Mirroring $repo..."
		payload=$(jq -n \
			--arg clone_addr "https://github.com/$GITHUB_USER/$repo.git" \
			--arg repo_name "$repo" \
			--arg auth_token "$GH_TOKEN" \
			'{
				clone_addr: $clone_addr,
				repo_name: $repo_name,
				mirror: true,
				private: true,
				auth_token: $auth_token,
				mirror_interval: "1h"
			}')
		result=$(curl -fsS -X POST "$GITEA_URL/api/v1/repos/migrate" \
			-H "Authorization: token $GITEA_TOKEN" \
			-H "Content-Type: application/json" \
			-d "$payload" 2>&1) || {
			echo "  x Failed: $result"
			continue
		}

		name=$(echo "$result" | jq -r '.name // empty')
		if [ -n "$name" ]; then
			echo "  + Created $name"
			created=$((created + 1))
		else
			msg=$(echo "$result" | jq -r '.message // "unknown error"')
			echo "  x Failed: $msg"
		fi
	fi
done

echo "Done! Created: $created, Skipped: $skipped"
