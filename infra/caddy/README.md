# Caddy Notes

## Snippet Model

Use imports to keep routing policy consistent:

- `auth`: shared security headers + compression + auth for user/admin services
- `auth-admin`: same as `auth`, but admin-only role policy
- `public`: shared security headers + compression for unauthenticated services
- `public-webhook`: `public` plus tighter IP-based request limiting
- `api-public`: `public` plus strict IP-based request limiting
- `cf-tls`: Cloudflare DNS challenge TLS settings for externally managed domains

For app stacks in `apps/*/docker-compose.yml`, use:

- `caddy.import: auth` for protected user/admin apps
- `caddy.import: auth-admin` for admin-only apps
- `caddy.import: public` for intentionally public apps

## Endpoint Rate Limiting (Auth)

Rate limiting is enabled with [`github.com/mholt/caddy-ratelimit`](https://github.com/mholt/caddy-ratelimit):

- `auth.jaw.dev`: portal-wide limiter
- `public-webhook`: webhook routes
- `api-public`: public API routes

The deployed Caddy image must include the `github.com/mholt/caddy-ratelimit` module.
