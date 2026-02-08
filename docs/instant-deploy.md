# Instant Deploy

Push a tag → image builds → home-ops updates → docker-cd deploys. No Renovate delays.

## How It Works

```
App repo (ufc, commit, etc.)
    ↓ push tag v1.0.0
GitHub Actions builds image to ghcr.io
    ↓
docker-cd-deploy-workflow updates home-ops
    ↓
docker-cd detects change and deploys (within 60s)
```

## Setup for New Apps

### 1. Add deploy job to release workflow

Update `.github/workflows/release.yml` in your app repo:

```yaml
name: Release

on:
  push:
    tags:
      - 'v*'

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    outputs:
      version: ${{ steps.version.outputs.VERSION }}

    steps:
      - uses: actions/checkout@v4

      - name: Log in to Container registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.repository_owner }}
          password: ${{ secrets.GH_TOKEN }}

      - name: Extract version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF#refs/tags/}" >> $GITHUB_OUTPUT

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.version.outputs.VERSION }}

  deploy:
    needs: build-and-push
    uses: wajeht/docker-cd-deploy-workflow/.github/workflows/deploy.yaml@main
    with:
      app-path: apps/your-app-name
      tag: ${{ needs.build-and-push.outputs.version }}
    secrets:
      GH_TOKEN: ${{ secrets.GH_TOKEN }}
```

### 2. Add GH_TOKEN secret to app repo

```bash
gh secret set GH_TOKEN -R wajeht/your-app -b "YOUR_PAT"
```

Token needs: `repo`, `packages:write`

### 3. Add to renovate ignoreDeps

In `home-ops/renovate.json`, add your image to prevent Renovate from also updating it:

```json
"ignoreDeps": [
  "ghcr.io/wajeht/ufc",
  "ghcr.io/wajeht/your-app"
]
```

## Creating a Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

Watch progress:
```bash
gh run watch -R wajeht/your-app
```

## docker-cd-deploy-workflow

Reusable workflow at `wajeht/docker-cd-deploy-workflow` that:
1. Checks out home-ops using GH_TOKEN
2. Updates image tag in `apps/{app}/docker-compose.yml`
3. Commits and pushes

### Inputs

| Input | Required | Default | Description |
|-------|----------|---------|-------------|
| `home-ops-repo` | No | `wajeht/home-ops` | Target repo |
| `app-path` | Yes | - | Path to app (e.g., `apps/ufc`) |
| `tag` | Yes | - | Image tag (e.g., `v1.0.0`) |

### Secrets

| Secret | Description |
|--------|-------------|
| `GH_TOKEN` | PAT with repo access |

## Apps Using Instant Deploy

- `bang`
- `calendar`
- `close-powerlifting`
- `commit`
- `favicon`
- `gains`
- `git`
- `ip`
- `jaw.dev` (www)
- `mm2us.com`
- `notify`
- `screenshot`
- `ufc`

## Renovate vs Instant Deploy

| | Renovate | Instant Deploy |
|---|----------|----------------|
| Speed | ~15min (polling) | ~1min |
| Setup | Mend UI config | GH_TOKEN secret |
| Use for | Third-party images | Your own images |
