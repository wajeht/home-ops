# Sonarr

Runtime config in `~/data/sonarr/` (not GitOps). Restore from Backrest; or re-apply below by hand.

## Quality — profile HD-1080p (only profile, mirrors Radarr)

- Allowed: WEBDL/WEBRip-1080p, Bluray-1080p. Cutoff WEB 1080p, upgrades on.
- Min format score: -1000 (junk formats below are rejected).

Size limits (MB/min):

| Quality            | Min | Preferred | Max |
| ------------------ | --- | --------- | --- |
| WEBDL/WEBRip-1080p | 0   | 15        | 100 |
| Bluray-1080p       | 0   | 30        | 150 |

## Release preference — usenet first, torrent fallback

Delay profile: prefer Usenet, usenet delay 0, torrent delay 60 min.

## Custom formats (scored in HD-1080p)

| Format                            | Score  |
| --------------------------------- | ------ |
| x265 (HD)                         | +100   |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 |
| LQ / LQ (Release Title)           | -10000 |
| Upscaled / BR-DISK                | -10000 |

No YTS format — YTS/YIFY is movies only, so LQ junk filters stay on (unlike Radarr).

## Indexers

Synced from Prowlarr (Full Sync) — don't edit here, overwritten each sync. RSS sync interval 60 min; older gaps need Wanted → Missing → Search.

## Download clients

| Client      | Host           | Category |
| ----------- | -------------- | -------- |
| qBittorrent | `gluetun:8085` | `sonarr` |
| SABnzbd     | `sabnzbd:8080` | `tv`     |
