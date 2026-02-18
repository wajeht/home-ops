# SSL/TLS Certificates

Traefik handles TLS automatically. `*.jaw.dev` uses Cloudflare DNS challenge.

## How It Works

1. Traefik obtains certs using Cloudflare DNS challenge.
2. `*.jaw.dev` is handled by wildcard TLS settings in `apps/traefik/docker-compose.yml`.
3. Apps only need Traefik labels and the `traefik` network.

## Config (apps/traefik/docker-compose.yml)

```yaml
- "--entrypoints.websecure.http.tls.domains[0].main=jaw.dev"
- "--entrypoints.websecure.http.tls.domains[0].sans=*.jaw.dev"
- "--entrypoints.websecure.http.tls.certresolver=cloudflare"
```

Non-wildcard domains can be routed with host rules:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`jaw.dev`) || Host(`www.jaw.dev`)"
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

## Cloudflare Token

Stored in `apps/traefik/.env.sops` as `CF_DNS_API_TOKEN`. Needs permissions:

- Zone:DNS:Edit
- Zone:Zone:Read

## Troubleshooting

Rate-limited or challenge failures:

- Check Traefik logs: `docker logs traefik`
- Verify `CF_DNS_API_TOKEN` has required zone permissions
- Confirm public DNS points to your host
