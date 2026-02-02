#!/bin/bash
# Setup GitHub mirrors in Gitea via API
# Run once after Gitea is deployed and you have an API token

set -e

GITEA_URL="https://git.wajeht.com"
GITEA_TOKEN="${GITEA_TOKEN:?Set GITEA_TOKEN env var}"
GITHUB_USER="wajeht"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"  # Optional, needed for private repos

# Repos to mirror (add your repos here)
REPOS=(
  "home-ops"
  "commit"
  # Add more repos...
)

for repo in "${REPOS[@]}"; do
  echo "Creating mirror for $repo..."

  curl -s -X POST "$GITEA_URL/api/v1/repos/migrate" \
    -H "Authorization: token $GITEA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"clone_addr\": \"https://github.com/$GITHUB_USER/$repo\",
      \"repo_name\": \"$repo\",
      \"mirror\": true,
      \"private\": false,
      \"auth_token\": \"$GITHUB_TOKEN\"
    }" && echo " ✓ $repo" || echo " ✗ $repo (may already exist)"
done

echo ""
echo "Done! Mirrors will sync every 8h."
echo "For instant sync, set up GitHub webhooks:"
echo "  URL: $GITEA_URL/api/v1/repos/$GITHUB_USER/{repo}/mirror-sync"
echo "  Secret: (create in Gitea)"
