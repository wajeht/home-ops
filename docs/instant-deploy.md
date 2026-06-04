# Instant Deploy

Push a tag → image builds → home-ops updates → docker-cd deploys. No Renovate delays.

Use this for your own `ghcr.io/wajeht/*` apps. Third-party images use [Renovate](renovate.md).

## How It Works

```
App repo
    ↓ push tag v1.0.0
GitHub Actions builds image to ghcr.io
    ↓
docker-cd-deploy-workflow updates home-ops
    ↓
docker-cd deploys by polling or `/api/sync`
```

## Setup for New Apps

### 1. Add deploy job to release workflow

Update `.github/workflows/release.yml` in your app repo:

```yaml
name: Release

on:
  push:
    tags:
      - "v*"

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
    uses: wajeht/docker-cd-deploy-workflow/.github/workflows/deploy.yaml@v0.0.25
    with:
      app-path: apps/your-app-name
      service-name: your-compose-service-name
      tag: ${{ needs.build-and-push.outputs.version }}
      url: https://your-app.jaw.dev
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

| Input           | Required | Default                       | Description                           |
| --------------- | -------- | ----------------------------- | ------------------------------------- |
| `home-ops-repo` | No       | `wajeht/home-ops`             | Target repo                           |
| `app-path`      | Yes      | -                             | Path to app. Example: `apps/ufc`      |
| `service-name`  | Yes      | -                             | Compose service to update             |
| `tag`           | Yes      | -                             | Image tag. Example: `v1.0.0`          |
| `url`           | No       | `https://<repo-name>.jaw.dev` | Production URL for GitHub Deployments |

### Secrets

| Secret     | Description          |
| ---------- | -------------------- |
| `GH_TOKEN` | PAT with repo access |

### Deploy Tracking

The workflow uses native GitHub Actions `environment:` which provides:

- "production" entry in the repo's Deployments sidebar
- Clickable URL link to the deployed app
- Deploy queue serialized with `concurrency: deploy-home-ops`

For custom domains outside `*.jaw.dev`, pass the `url` input:

```yaml
uses: wajeht/docker-cd-deploy-workflow/.github/workflows/deploy.yaml@v0.0.25
with:
  app-path: apps/close-powerlifting
  service-name: close-powerlifting
  tag: ${{ needs.build.outputs.tag }}
  url: https://closepowerlifting.com
```

## Which Apps Use It

Use instant deploy for apps you build and publish as `ghcr.io/wajeht/*`.

## Temporary PR Apps

App repos can also create preview stacks in `home-ops` with the reusable temp workflows.

- `temp-deploy` deploys `apps/<app>-pr-<N>` at `https://pr-<N>-<app>.jaw.dev` with production middleware labels
- `temp-deploy-with-auth` deploys the same preview with `oauth2-admin@file`
- if both labels are present, auth wins
- removing one temp label redeploys with the remaining mode
- removing the last temp label, or closing the PR, removes the preview stack

Use `wajeht/docker-cd-deploy-workflow/.github/workflows/temp-deploy.yaml@v0.0.25` with:

```yaml
with:
  app-path: apps/your-app
  service-name: your-compose-service
  tag: ${{ needs.temp-build.outputs.tag }}
  auth-middleware: ${{ contains(github.event.pull_request.labels.*.name, 'temp-deploy-with-auth') && 'oauth2-admin@file' || '' }}
```

Use the matching cleanup workflow and only run it when the PR closes or the last temp label is removed.

Source of truth:

```bash
rg 'image: ghcr.io/wajeht/' apps/*/docker-compose.yml
```

## Renovate vs Instant Deploy

|         | Renovate           | Instant Deploy  |
| ------- | ------------------ | --------------- |
| Speed   | ~15min polling     | ~1min           |
| Setup   | Mend UI config     | GH_TOKEN secret |
| Use for | Third-party images | Your own images |
