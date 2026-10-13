# Renovate Auto-Updates

Renovate automatically creates PRs when third-party Docker image versions are available.

## How It Works

```
new third-party image tag available
    ↓
Renovate detects new version every 3 hours
    ↓
waits for minimumReleaseAge
    ↓
creates PR
    ↓
CI passes → GitHub auto-merges eligible updates
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

### Mend UI Setup

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

| Image              | Action                       |
| ------------------ | ---------------------------- |
| `ghcr.io/wajeht/*` | Ignored; uses instant deploy |
| Third-party images | Creates PR for review        |

## Auto-Merge

Shared config: [wajeht/renovate-config](https://github.com/wajeht/renovate-config)

| Update | Release Age | Auto-Merge |
| ------ | ----------- | ---------- |
| Patch  | 0 days      | Yes        |
| Minor  | 1 day       | Yes        |
| Major  | 3 days      | No         |
| Digest | 0 days      | Yes        |

Requires `platformAutomerge: true` + GitHub branch protection with required status checks and **"Require branches to be up to date before merging"** with `strict: true`. Without `strict`, GitHub can merge PRs with stale lock files when multiple Renovate PRs are open simultaneously.

## Media Release Channels

Media apps use full upstream application versions so Renovate can compare actual builds, rather than treating a channel suffix as permanent compatibility.

- qBittorrent accepts only three-part versions with `-libtorrentv1` or `-libtorrentv2`, and preserves the current variant. Legacy distro tags such as `20.04.1` cannot replace it.
- Gitea accepts only complete three-part release tags. Legacy two-part tags such as `28.1` are excluded; the current `1.27` pin can still receive complete release versions.
- Radarr, Prowlarr, and Sonarr use `version-X.Y.Z.BUILD` tags. The regex also recognizes the existing `nightly-version-` and `develop-version-` pins; an explicit stable-tag allowlist excludes new prerelease candidates, including newer prereleases of the same application version.
- Bazarr recognizes its existing `development-version-vX.Y.Z-beta.N` pin and accepts only stable `version-vX.Y.Z` candidates.
- Version and digest updates for these four media apps require manual review. The existing LinuxServer rollback restriction remains in place.

### Stable Transition

Registry versions checked on October 13, 2026:

| App      | Previous pinned build | Current stable build | Change                                           |
| -------- | --------------------- | -------------------- | ------------------------------------------------ |
| Sonarr   | 4.0.20.3012 develop   | 4.0.20.3014          | Move forward to stable                           |
| Radarr   | 6.4.4.10741 nightly   | 6.4.4.10685          | Keep the existing digest until stable catches up |
| Prowlarr | 2.6.5.5664 nightly    | 2.6.5.5623           | Keep the existing digest until stable catches up |
| Bazarr   | 1.6.3 beta.11         | 1.6.2                | Keep the existing digest until stable catches up |

The three held images have full-version tag aliases verified against their unchanged registry digests. Renovate can propose an equal-build stable release or a newer stable release, but cannot downgrade to the current older stable builds. Do not swap these pins to `latest` to force the transition.

Before merging any media image update, create an app backup and verify its dump is present. After deployment, check startup logs, the app UI, indexer/download-client connections, and an existing library entry. Image rollback alone may not undo database migrations; keep the pre-update backup.

## Troubleshooting

### "Failed to look up docker package ghcr.io/..."

1. Check GH_TOKEN has `read:packages` scope
2. Verify secret is added in Mend UI
3. Verify hostRules in renovate.json references `{{ secrets.GH_TOKEN }}`
4. Retry the failed job in Renovate dashboard

### Token Requirements

Create a GitHub **classic** PAT with:

- `read:packages` scope

Fine-grained tokens do NOT work for packages.
