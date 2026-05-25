# oauth2-proxy

Google OAuth forward-auth via [oauth2-proxy](https://github.com/oauth2-proxy/oauth2-proxy).

- `oauth2-admin` uses `admin-emails.txt`.
- `oauth2-media` uses `media-emails.txt`.
- Traefik middlewares live in `apps/traefik/dynamic.yml`.

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

## Healthcheck

The static `portcheck` binary is mounted into both containers for TCP healthchecks on port 4180.
