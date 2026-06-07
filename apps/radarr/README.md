# Radarr

Runtime config lives in `~/data/radarr/` on the server, not in this repo. This documents the settings applied via UI/API so they can be restored.

## Quality

Primary profile: **HD-1080p** (used by virtually all movies).

- **Allowed:** WEB 1080p (WEBDL + WEBRip), Bluray-1080p
- **Cutoff:** WEB 1080p, upgrades enabled
- **Min format score:** -1000 (hard-rejects junk formats below)

Size limits (Settings → Quality, MB/min):

| Quality            | Min | Preferred | Max |
| ------------------ | --- | --------- | --- |
| WEBDL/WEBRip-1080p | 0   | 15        | 100 |
| Bluray-1080p       | 0   | 30        | 150 |

## Custom Formats (TRaSH)

[TRaSH Guides](https://trash-guides.info) formats, scored in the HD-1080p profile:

| Format                            | Score  |
| --------------------------------- | ------ |
| x265 (HD)                         | +100   |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 |
| LQ / LQ (Release Title)           | -10000 |
| Upscaled / BR-DISK / Extras       | -10000 |

x265 is preferred (~half the size of x264 at 1080p); negative scores block junk releases entirely via the min format score. Other imported formats (tiers, streaming services) remain at 0.

## Indexers

Synced from Prowlarr (Full Sync) — do not edit indexers in Radarr, changes are overwritten every sync (see `apps/prowlarr/README.md`).

## Download Clients

| Client      | Host           | Category |
| ----------- | -------------- | -------- |
| qBittorrent | `gluetun:8085` | `radarr` |
| SABnzbd     | `sabnzbd:8080` | `movies` |
