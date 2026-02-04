# Gitea - GitHub Mirror

Auto-mirrors GitHub repos to self-hosted Gitea.

## Setup

After deploy:

1. Go to https://gitea.jaw.dev → create admin account
2. Settings → Applications → Generate API token
3. Run mirror script:

```bash
GITEA_TOKEN=your_token GITHUB_TOKEN=your_gh_pat ./setup-mirrors.sh
```

## Instant Sync via Webhook

Instead of waiting 8h, trigger immediate sync on push.

On GitHub, for each repo: Settings → Webhooks → Add webhook:

| Field | Value |
|-------|-------|
| URL | `https://gitea.jaw.dev/api/v1/repos/wajeht/{repo}/mirror-sync` |
| Content type | `application/json` |
| Events | Just `push` |

Add custom header:
```
Authorization: token YOUR_GITEA_TOKEN
```

## Add More Mirrors

Edit `setup-mirrors.sh` and add repos to the `REPOS` array, then re-run.

## Manual Sync

```bash
curl -X POST "https://gitea.jaw.dev/api/v1/repos/wajeht/REPO/mirror-sync" \
  -H "Authorization: token YOUR_GITEA_TOKEN"
```
