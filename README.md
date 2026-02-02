# home-ops

GitOps for Docker Compose using [doco-cd](https://github.com/kimdre/doco-cd).

## Structure

```
home-ops/
├── .doco-cd.yml        # root orchestrator
├── infrastructure/     # core services (traefik, doco-cd)
└── apps/               # application stacks
```

## Quick Start

```bash
# 1. Configure environment
cp .env.example .env
vim .env

# 2. Bootstrap
make bootstrap

# 3. Push to git - doco-cd handles the rest
git add . && git commit -m "init" && git push
```

## Usage

### Add New App

```bash
mkdir apps/myapp
# create apps/myapp/docker-compose.yml
git add . && git commit -m "add myapp" && git push
# deployed within 60s
```

### Remove App

```bash
rm -rf apps/myapp
git add . && git commit -m "remove myapp" && git push
# removed within 60s (auto_discover.delete: true)
```

### Manual Deploy

```bash
make deploy APP=apps/homepage
```

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Initial setup (network + traefik + doco-cd) |
| `make status` | Show all running containers |
| `make logs` | Tail doco-cd logs |
| `make deploy APP=path` | Manual deploy a specific app |
| `make down APP=path` | Stop a specific app |
| `make pull` | Pull latest images for all apps |
| `make clean` | Stop all and prune |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TZ` | Timezone |
| `DOMAIN` | Base domain for traefik routing |
| `GIT_ACCESS_TOKEN` | GitHub/Gitea token |
| `GITOPS_REPO_URL` | This repo's clone URL |

## How It Works

1. **doco-cd** polls this repo every 60s
2. Detects changes in `infrastructure/` and `apps/`
3. Auto-deploys new/changed stacks
4. Auto-removes deleted stacks
5. All apps route through **traefik** reverse proxy
