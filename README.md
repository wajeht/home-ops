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

## Subdomains & Routing

Apps get subdomains via Traefik labels. Set `DOMAIN` in `.env`:

```bash
DOMAIN=example.com
```

Results in:
- `whoami.example.com` → whoami
- `home.example.com` → homepage
- `traefik.example.com` → dashboard

### Adding Subdomain to New App

```yaml
services:
  myapp:
    image: myimage
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN}`)"
      - "traefik.http.routers.myapp.entrypoints=websecure"
      - "traefik.http.routers.myapp.tls=true"
      - "traefik.http.routers.myapp.tls.certresolver=letsencrypt"

networks:
  default:
    name: traefik
    external: true
```

## HTTPS / TLS

Using Let's Encrypt with Cloudflare DNS challenge (works behind NAT).

### Setup

1. Create Cloudflare API token with `Zone:DNS:Edit` permission
2. Configure `.env`:
   ```bash
   DOMAIN=yourdomain.com
   ACME_EMAIL=you@email.com
   CF_DNS_API_TOKEN=your_cloudflare_token
   ```
3. Traefik auto-provisions certs

### Other DNS Providers

Edit `infrastructure/traefik/docker-compose.yml`, change provider:
- `cloudflare`
- `route53` (AWS)
- `digitalocean`
- `duckdns`
- `namecheap`

Full list: https://doc.traefik.io/traefik/https/acme/#providers

### Local Network (No Public Domain)

Options:
- **mkcert** - local CA certs
- **Tailscale** - auto HTTPS via MagicDNS
- **HTTP only** - remove TLS labels

## Commands

| Command | Description |
|---------|-------------|
| `make bootstrap` | Initial setup (network + traefik + doco-cd) |
| `make status` | Show all running containers |
| `make logs` | Tail doco-cd logs |
| `make deploy APP=path` | Manual deploy a specific app |
| `make down APP=path` | Stop a specific app |
| `make pull` | Pull latest images for all apps |
| `make clean` | Stop all + prune |

## Environment Variables

| Variable | Description |
|----------|-------------|
| `TZ` | Timezone |
| `DOMAIN` | Base domain for traefik routing |
| `GIT_ACCESS_TOKEN` | GitHub/Gitea token |
| `GITOPS_REPO_URL` | This repo's clone URL |
| `ACME_EMAIL` | Let's Encrypt email |
| `CF_DNS_API_TOKEN` | Cloudflare API token |

## How It Works

1. **doco-cd** polls this repo every 60s
2. Detects changes in `infrastructure/` and `apps/`
3. Auto-deploys new/changed stacks
4. Auto-removes deleted stacks
5. **Traefik** handles routing + TLS
