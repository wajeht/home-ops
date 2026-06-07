# Seerr

Runtime config in `~/data/seerr/settings.json` (not GitOps).

## Arr connections

Requests auto-send to Sonarr/Radarr → Prowlarr indexers → SAB/qBittorrent → Plex.

| App    | Host          | Profile  | Root           | Default |
| ------ | ------------- | -------- | -------------- | ------- |
| Sonarr | `sonarr:8989` | HD-1080p | `/data/tv`     | yes     |
| Radarr | `radarr:7878` | HD-1080p | `/data/movies` | yes     |

API keys live in `settings.json`. If a key is regenerated, update via Settings → Services (or PUT `/api/v1/settings/{sonarr,radarr}/{id}` — strip the read-only `id` from the body).
