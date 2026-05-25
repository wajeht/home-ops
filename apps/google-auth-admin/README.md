# google-auth-admin

Google OAuth forward-auth for admin users via [thomseddon/traefik-forward-auth](https://github.com/thomseddon/traefik-forward-auth).

Most apps use `WHITELIST_ADMINS`. Media-facing apps (`plex.jaw.dev`, `seerr.jaw.dev`, `convertx.jaw.dev`) have host rules that use `WHITELIST_MEDIA`.

## Healthcheck

The image is scratch-based (no shell, no wget/curl), so a static [portcheck](https://github.com/tarampampam/microcheck) binary (63KB) is mounted into the container for TCP healthchecks on port 4181.

To update portcheck:

```bash
curl -sL https://github.com/tarampampam/microcheck/releases/download/v1.3.0/linux-amd64.tar.gz | tar xz portcheck
```
