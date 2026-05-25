# Renovate Auto-Updates

Renovate automatically creates PRs when third-party Docker image versions are available.

> **Note:** Your own images (ghcr.io/wajeht/\*) use [instant deploy](instant-deploy.md) instead.

Use this doc for third-party image update behavior and Renovate credentials.

## How It Works

```
new third-party image tag available
    ↓
Renovate detects new version (every 3 hours)
    ↓
waits for minimumReleaseAge (patch: 0d, minor: 1d, major: 3d)
    ↓
creates PR
    ↓
CI passes → GitHub auto-merges (patch/minor/digest)
    ↓
docker-cd deploys
```

Major updates require manual review and merge.

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
  "ignoreDeps": ["ghcr.io/wajeht/bang", "ghcr.io/wajeht/ufc", "..."]
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

| Image              | Action                        |
| ------------------ | ----------------------------- |
| `ghcr.io/wajeht/*` | Ignored (uses instant deploy) |
| Third-party images | Creates PR for review         |

## Auto-Merge

Shared config: [wajeht/renovate-config](https://github.com/wajeht/renovate-config)

| Update | Release Age | Auto-Merge |
| ------ | ----------- | ---------- |
| Patch  | 0 days      | Yes (PR)   |
| Minor  | 1 day       | Yes (PR)   |
| Major  | 3 days      | No         |
| Digest | 0 days      | Yes (PR)   |

Requires `platformAutomerge: true` + GitHub branch protection with required status checks and **"Require branches to be up to date before merging" (`strict: true`)**. Without `strict`, GitHub can merge PRs with stale lock files when multiple Renovate PRs are open simultaneously.

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
