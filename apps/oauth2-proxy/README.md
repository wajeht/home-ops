# oauth2-proxy

Google OAuth forward-auth via [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy).

- `oauth2-admin` uses admin email variables from `.env.sops`.
- `oauth2-media` uses media email variables from `.env.sops`.
- Traefik middlewares live in `apps/traefik/dynamic.yml`.
- A valid `X-Bypass-Key` skips OAuth through the private `auth-bypass` gate in
  `apps/traefik/`.

Protected apps use one of these labels:

```yaml
- "traefik.http.routers.myapp.middlewares=oauth2-admin@file"
- "traefik.http.routers.mediaapp.middlewares=oauth2-media@file"
```

Google OAuth redirect URIs:

```text
https://auth.jaw.dev/oauth2/admin/callback
https://auth.jaw.dev/oauth2/media/callback
```

Only the `/oauth2/admin/*` and `/oauth2/media/*` paths are routed. `auth.jaw.dev` root is intentionally not an app.

Cookie lifetimes:

- Admin: 24 hours
- Media: 7 days

## Access Lists

Edit `apps/oauth2-proxy/.env.sops` to add or remove users:

- `OAUTH2_ADMIN_EMAIL_*` controls admin access.
- `OAUTH2_MEDIA_EMAIL_*` controls media access.

Docker-cd decrypts `.env.sops` to `.env`. Docker Compose turns those variables into the runtime files oauth2-proxy reads at `/etc/oauth2-proxy/*-emails.txt`.

## Healthcheck

The static `portcheck` binary is mounted into both containers for TCP healthchecks on port 4180.
