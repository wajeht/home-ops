#!/bin/bash
# Sync all GitHub repos to Gitea as mirrors
# Usage: ./mirror-sync.sh
# Runs on server via cron

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Config
GITEA_URL="https://gitea.jaw.dev"
GITEA_TOKEN_FILE="${GITEA_TOKEN_FILE:-$SCRIPT_DIR/.gitea-token}"
GITHUB_TOKEN_FILE="${GITHUB_TOKEN_FILE:-/home/jaw/.config/gh-token}"
GITHUB_USER="wajeht"

# Load tokens
GITEA_TOKEN=$(cat "$GITEA_TOKEN_FILE" 2>/dev/null || echo "")
GITHUB_TOKEN=$(cat "$GITHUB_TOKEN_FILE" 2>/dev/null || echo "")

if [ -z "$GITEA_TOKEN" ] || [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: Missing tokens"
  echo "  GITEA_TOKEN_FILE: $GITEA_TOKEN_FILE"
  echo "  GITHUB_TOKEN_FILE: $GITHUB_TOKEN_FILE"
  exit 1
fi

# Get all GitHub repos (paginated)
echo "Fetching GitHub repos for $GITHUB_USER..."
GITHUB_REPOS=""
page=1
while true; do
  repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
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
  repos=$(curl -s -H "Authorization: token $GITEA_TOKEN" \
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
    echo "→ Mirroring $repo..."
    result=$(curl -s -X POST "$GITEA_URL/api/v1/repos/migrate" \
      -H "Authorization: token $GITEA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"clone_addr\": \"https://github.com/$GITHUB_USER/$repo.git\",
        \"repo_name\": \"$repo\",
        \"mirror\": true,
        \"private\": true,
        \"auth_token\": \"$GITHUB_TOKEN\",
        \"mirror_interval\": \"8h\"
      }" 2>&1)

    name=$(echo "$result" | jq -r '.name // empty')
    if [ -n "$name" ]; then
      echo "  ✓ Created $name"
      created=$((created + 1))
    else
      msg=$(echo "$result" | jq -r '.message // "unknown error"')
      echo "  ✗ Failed: $msg"
    fi
  fi
done

echo "Done! Created: $created, Skipped: $skipped"
