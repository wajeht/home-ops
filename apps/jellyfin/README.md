# Jellyfin Media Server

Jellyfin with Intel Quick Sync hardware transcoding. Shares the same media library as Plex (read-only mounts).

## Hardware Transcoding

Intel Quick Sync is enabled by passing `/dev/dri` to the container:

```yaml
devices:
  - /dev/dri:/dev/dri
```

`/dev/dri` is also passed to Plex. Both can use it, but simultaneous transcodes on both services will compete for the same GPU.

## Verify Hardware Transcoding

Check device access:

```bash
docker exec jellyfin ls -la /dev/dri
```

Should show:

```
card0       - GPU device
renderD128  - Render device (used for transcoding)
```

## Enable in Jellyfin

1. Go to Dashboard → Playback
2. Set "Hardware acceleration" to "Intel QuickSync (QSV)"
3. Set "Transcoding path" to `/transcode` (RAM-backed tmpfs)

## Auth

Jellyfin is behind `oauth2-media@file` — only emails in the media allowlist (see `apps/oauth2-proxy/.env.sops`) can reach the login page. Create matching local Jellyfin users for each allowed account.

## Required: Known Proxies (one-time post-install)

Behind Traefik, Jellyfin sees the Traefik container IP as the client, which breaks rate limiting and IP-based logging. Fix once after first boot:

1. Dashboard → Networking → **Known proxies**
2. Add the Docker `traefik` network CIDR (find it with `docker network inspect traefik | jq -r '.[0].IPAM.Config[0].Subnet'` — typically `172.18.0.0/16` or similar)
3. Save and restart Jellyfin

Use the CIDR, not a single IP — Traefik's container IP rotates on every restart.

## Volumes

| Path      | Purpose                        |
| --------- | ------------------------------ |
| `/config` | Jellyfin database and settings |
| `/movies` | Movie library (read-only)      |
| `/tv`     | TV show library (read-only)    |
| `/music`  | Music library (read-only)      |
