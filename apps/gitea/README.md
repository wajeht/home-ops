# Gitea - GitHub Mirror

Auto-mirrors all GitHub repos to self-hosted Gitea.

## How It Works

1. `gitea` - Main Gitea server
2. `mirror-sync` - Sidecar that syncs GitHub repos every 6h

## Setup

1. Deploy stack: `docker stack deploy -c docker-compose.yml gitea`
2. Go to https://gitea.jaw.dev → create admin account
3. Settings → Applications → Generate API token
4. Add tokens to `.env.sops`:

```bash
sops .env.sops
# Add:
# GITEA_TOKEN=your_gitea_token
# GH_TOKEN=your_github_pat
```

5. Redeploy to pick up tokens

## Tokens Required

| Token | Scope | Purpose |
|-------|-------|---------|
| GITEA_TOKEN | Gitea API token | Create mirrors |
| GH_TOKEN | GitHub PAT with `repo` scope | Read private repos |

## Manual Sync

Trigger sync immediately:

```bash
docker service update --force gitea_mirror-sync
```

Or call API directly:

```bash
curl -X POST "https://gitea.jaw.dev/api/v1/repos/wajeht/REPO/mirror-sync" \
  -H "Authorization: token YOUR_GITEA_TOKEN"
```

## Logs

```bash
docker service logs gitea_mirror-sync -f
```
