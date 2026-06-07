# Sonarr

Runtime config lives in `~/data/sonarr/` on the server, not in this repo. This documents the settings applied via UI/API so they can be restored.

## Quality

Single profile: **HD-1080p** (all stock profiles deleted). Mirrors Radarr.

- **Allowed:** WEBDL-1080p, WEBRip-1080p, Bluray-1080p (no HDTV/SD/4K)
- **Cutoff:** WEB 1080p, upgrades enabled
- **Min format score:** -1000 (hard-rejects junk formats below)

Size limits (Settings → Quality, MB/min):

| Quality            | Min | Preferred | Max |
| ------------------ | --- | --------- | --- |
| WEBDL/WEBRip-1080p | 0   | 15        | 100 |
| Bluray-1080p       | 0   | 30        | 150 |

## Custom Formats (TRaSH)

Imported from [TRaSH Guides](https://trash-guides.info) sonarr JSONs, scored in the HD-1080p profile:

| Format                            | Score  |
| --------------------------------- | ------ |
| x265 (HD)                         | +100   |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 |
| LQ / LQ (Release Title)           | -10000 |
| Upscaled / BR-DISK                | -10000 |

x265 is preferred (~half the size of x264 at 1080p); negative scores block junk releases entirely via the min format score.

## Indexers

Synced from Prowlarr (Full Sync) — do not edit indexers in Sonarr, changes are overwritten every sync. RSS/search flags come from Prowlarr's sync profile (see `apps/prowlarr/README.md`).

RSS sync interval: 60 min (Settings → Indexers → Options). RSS only grabs releases published after it runs; older gaps need Wanted → Missing → Search.

## Download Clients

| Client      | Host           | Category |
| ----------- | -------------- | -------- |
| qBittorrent | `gluetun:8085` | `sonarr` |
| SABnzbd     | `sabnzbd:8080` | `tv`     |

Credentials live in each client's own config under `~/data/`.
