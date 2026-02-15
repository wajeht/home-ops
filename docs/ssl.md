# SSL/TLS Certificates

Traefik handles SSL automatically using Let's Encrypt with Cloudflare DNS challenge.

## How It Works

1. Traefik requests a **wildcard certificate** for `jaw.dev` + `*.jaw.dev`
2. Uses Cloudflare DNS challenge (creates `_acme-challenge` TXT records)
3. All apps automatically use this wildcard cert - no per-app config needed

## Config (apps/traefik/docker-compose.yml)

```yaml
command:
  # ACME with Cloudflare DNS
  - "--certificatesresolvers.cloudflare.acme.email=mail@jaw.dev"
  - "--certificatesresolvers.cloudflare.acme.storage=/certs/acme.json"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge=true"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge.provider=cloudflare"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge.delaybeforecheck=30"
  - "--certificatesresolvers.cloudflare.acme.dnschallenge.resolvers=1.1.1.1:53,1.0.0.1:53"
  # Wildcard cert at entrypoint level
  - "--entrypoints.websecure.http.tls.domains[0].main=jaw.dev"
  - "--entrypoints.websecure.http.tls.domains[0].sans=*.jaw.dev"
  - "--entrypoints.websecure.http.tls.certresolver=cloudflare"
```

## App Config

Apps don't need `certresolver` labels - the wildcard handles all `*.jaw.dev` subdomains:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

## Cloudflare Token

Stored in `apps/traefik/.env.sops` as `CF_DNS_API_TOKEN`. Needs permissions:

- Zone:DNS:Edit
- Zone:Zone:Read

## Troubleshooting

**Rate limited by Let's Encrypt:**

- Wait 1 hour for rate limit to reset
- Check logs: `docker logs traefik`

**DNS propagation issues:**

- The 30s delay before check helps with propagation
- Using 1.1.1.1 resolvers sees Cloudflare changes faster

**Certificate not obtained:**

1. Check acme.json: `docker exec <traefik> cat /certs/acme.json`
2. Verify Cloudflare token has correct permissions
3. Check for stale `_acme-challenge` TXT records in Cloudflare DNS
