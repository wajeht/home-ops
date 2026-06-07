# Seerr

Runtime config lives in `~/data/seerr/settings.json` on the server, not in this repo.

## Arr Connections

Requests are auto-sent to Sonarr/Radarr; downloads then flow through Prowlarr indexers → qBittorrent/SABnzbd → import → Plex.

| App    | Host          | Profile  | Root           | Default |
| ------ | ------------- | -------- | -------------- | ------- |
| Sonarr | `sonarr:8989` | HD-1080p | `/data/tv`     | yes     |
| Radarr | `radarr:7878` | HD-1080p | `/data/movies` | yes     |

API keys are stored in `settings.json` — if Sonarr/Radarr keys are regenerated, update via Settings → Services (or the `/api/v1/settings/{sonarr,radarr}/{id}` endpoint; the `id` body field is read-only, strip it on PUT).
