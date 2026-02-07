# Renovate Auto-Updates

Renovate automatically creates PRs when third-party Docker image versions are available.

> **Note:** Your own images (ghcr.io/wajeht/*) use [instant deploy](instant-deploy.md) instead.

## How It Works

```
new third-party image tag available
    ↓
Renovate detects new version
    ↓
creates PR for review
    ↓
merge PR → doco-cd deploys
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
  "ignoreDeps": [
    "ghcr.io/wajeht/bang",
    "ghcr.io/wajeht/ufc",
    "..."
  ]
}
```

- `hostRules` - auth for private ghcr.io images
- `ignoreDeps` - your images handled by instant deploy

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

## Behavior

| Image | Action |
|-------|--------|
| `ghcr.io/wajeht/*` | Ignored (uses instant deploy) |
| Third-party images | Creates PR for review |

## Troubleshooting

### "Failed to look up docker package ghcr.io/..."

1. Check GH_TOKEN has `read:packages` scope
2. Verify secret is added in Mend UI
3. Verify hostRules in renovate.json references `{{ secrets.GH_TOKEN }}`
4. Retry the failed job in Renovate dashboard

### Token Requirements

Create a GitHub **classic** PAT with:
- `read:packages` scope (required)

Fine-grained tokens do NOT work for packages.
