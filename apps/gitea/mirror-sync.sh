#!/bin/bash
# Sync all GitHub repos to Gitea as mirrors
# Usage: ./mirror-sync.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

GITEA_URL="${GITEA_URL:-https://gitea.jaw.dev}"
GITHUB_USER="${GITHUB_USER:-wajeht}"

# Get all GitHub repos (paginated)
echo "Fetching GitHub repos for $GITHUB_USER..."
GITHUB_REPOS=""
page=1
while true; do
  repos=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
    "https://api.github.com/user/repos?per_page=100&page=$page&affiliation=owner" | jq -r '.[].name')
  [ -z "$repos" ] && break
  GITHUB_REPOS="$GITHUB_REPOS $repos"
  ((page++))
done

# Get existing Gitea repos
echo "Fetching existing Gitea repos..."
GITEA_REPOS=$(curl -s -H "Authorization: token $GITEA_TOKEN" \
  "$GITEA_URL/api/v1/user/repos?limit=200" | jq -r '.[].name')

# Create mirrors for missing repos
for repo in $GITHUB_REPOS; do
  if echo "$GITEA_REPOS" | grep -qx "$repo"; then
    echo "✓ $repo already exists"
  else
    echo "→ Creating mirror for $repo..."
    curl -s -X POST "$GITEA_URL/api/v1/repos/migrate" \
      -H "Authorization: token $GITEA_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{
        \"clone_addr\": \"https://github.com/$GITHUB_USER/$repo.git\",
        \"repo_name\": \"$repo\",
        \"mirror\": true,
        \"private\": true,
        \"auth_token\": \"$GITHUB_TOKEN\",
        \"mirror_interval\": \"8h\"
      }" | jq -r '.name // .message'
  fi
done

echo "Done!"
