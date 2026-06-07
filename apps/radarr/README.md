# Radarr

Runtime config in `~/data/radarr/` (not GitOps). Restore from Backrest; or re-apply below by hand.

## Quality — profile HD-1080p (only profile)

- Allowed: WEBDL/WEBRip-1080p, Bluray-1080p. Cutoff WEB 1080p, upgrades on.
- Min format score: 0 (no score rejection — keeps YTS).

Size limits (MB/min) — max is a hard cap:

| Quality            | Min | Preferred | Max |
| ------------------ | --- | --------- | --- |
| WEBDL/WEBRip-1080p | 0   | 15        | 40  |
| Bluray-1080p       | 0   | 30        | 40  |

## Release preference — usenet first, YTS fallback

Delay profile: prefer Usenet, usenet delay 0, torrent delay 60 min.

## Custom formats (scored in HD-1080p)

| Format                            | Score  |
| --------------------------------- | ------ |
| YTS (`\b(YTS\|YIFY)\b`)           | +150   |
| x265 (HD)                         | +100   |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 |
| BR-DISK / Upscaled / Extras       | -10000 |
| LQ / LQ (Release Title)           | 0      |

LQ kept at 0 on purpose — TRaSH's LQ list bans YTS/YIFY; don't re-enable it or set min score negative.

## Download clients

| Client      | Host           | Category |
| ----------- | -------------- | -------- |
| qBittorrent | `gluetun:8085` | `radarr` |
| SABnzbd     | `sabnzbd:8080` | `movies` |

## Indexers

Synced from Prowlarr (Full Sync) — don't edit here, overwritten each sync.

## Resources

`memory: 2G` (was 1G — bulk search/delete OOM'd the 1G cap).

## Shrinking oversized existing files

Radarr never auto-downgrades, so shrink via delete-file → re-search. Worklist: `redownload-list.md` (repo root, gitignored). Only delete once a clean 1080p replacement is grabbable (rejections are existing-file-only); it re-imports under the 40 MB/min cap. Clearing the queue with `blocklist=true` blocklists those releases — only do it for bad/big ones.
