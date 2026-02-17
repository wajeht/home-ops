# Caddy Notes

## Snippet Model

Use imports to keep routing policy consistent:

- `auth`: shared security headers + compression + auth for user/admin services
- `auth-admin`: same as `auth`, but admin-only role policy
- `public`: shared security headers + compression for unauthenticated services
- `cf-tls`: Cloudflare DNS challenge TLS settings for externally managed domains

For app stacks in `apps/*/docker-compose.yml`, use:

- `caddy.import: auth` for protected user/admin apps
- `caddy.import: auth-admin` for admin-only apps
- `caddy.import: public` for intentionally public apps

## Endpoint Rate Limiting (Auth)

`home-ops` Caddy config currently does **not** enable endpoint rate limiting because the
deployed custom image (`ghcr.io/wajeht/docker-cd-caddy`) does not include a rate-limit plugin.

To enable this in the future:

1. In `docker-cd-caddy`, add `github.com/mholt/caddy-ratelimit` to `xcaddy build`.
2. Publish a new immutable image tag.
3. Update `infra/caddy/docker-compose.yml` to use that new image tag.
4. Add rate-limit rules for `auth.jaw.dev` endpoints in `infra/caddy/Caddyfile`.

Keep rate limits focused on auth paths first (`/auth/*`) to avoid affecting normal app traffic.
