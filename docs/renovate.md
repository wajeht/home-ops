# Renovate Auto-Updates

Renovate automatically creates PRs (or auto-merges) when new image versions are available.

## How It Works

```
new image tag pushed to ghcr.io
    ↓
Renovate detects new version
    ↓
auto-merges to home-ops (for your images)
    ↓
doco-cd deploys
```

## Configuration

### renovate.json

```json
{
  "hostRules": [
    {
      "matchHost": "ghcr.io",
      "hostType": "docker",
      "username": "wajeht",
      "password": "{{ secrets.GH_TOKEN }}"
    }
  ],
  "packageRules": [
    {
      "matchPackagePatterns": ["^ghcr\\.io/wajeht/"],
      "automerge": true
    }
  ]
}
```

### Mend UI Setup (Required for Private Images)

1. Go to https://developer.mend.io
2. Select `wajeht/home-ops`
3. Go to **Settings** → **Credentials**
4. **Add Secret**:
   - Name: `GH_TOKEN`
   - Value: Your GitHub PAT with `read:packages` scope
5. **Add Host Rule**:
   - Description: `ghcr.io private registry`
   - Host Type: `docker`
   - HostUrl: `ghcr.io`
   - Username: `wajeht`
   - Select Secret: `GH_TOKEN`

**Important:** You need BOTH:
- Secret stored in Mend UI
- hostRules in renovate.json referencing it with `{{ secrets.GH_TOKEN }}`

## Behavior

| Image | Action |
|-------|--------|
| `ghcr.io/wajeht/*` | Auto-merge (your private images) |
| Other images | Creates PR for review |

## Creating a Release

```bash
# In your app repo (e.g., hello-world)
git tag v1.0.0
git push origin v1.0.0
# → CI builds image
# → Renovate detects and auto-merges
# → doco-cd deploys
```

## Troubleshooting

### "Failed to look up docker package ghcr.io/wajeht/..."

1. Check GH_TOKEN has `read:packages` scope
2. Verify secret is added in Mend UI
3. Verify hostRules in renovate.json references `{{ secrets.GH_TOKEN }}`
4. Retry the failed job in Renovate dashboard

### Token Requirements

Create a GitHub **classic** PAT with:
- `read:packages` scope (required)

Fine-grained tokens do NOT work for packages.
