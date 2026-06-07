# Radarr

Runtime config lives in `~/data/radarr/` on the server, not in this repo. This documents the settings applied via UI/API so they can be restored.

## If the server is gone (restore)

1. **Primary:** restore `~/data/radarr/` (and `sonarr`, `prowlarr`, `seerr`, `sabnzbd`) from Backrest — see `docs/disaster-recovery.md`. This brings back the full DB including everything below; no manual steps needed.
2. **Fallback** (config lost / starting fresh): re-apply the settings in this README by hand via the UI. The arr apps auto-discover and deploy from compose; only the runtime settings here need redoing.

## Quality

Primary profile: **HD-1080p** (used by virtually all movies).

- **Allowed:** WEB 1080p (WEBDL + WEBRip), Bluray-1080p
- **Cutoff:** WEB 1080p, upgrades enabled
- **Min format score:** 0 (no score-based rejection — see note below)

Size limits (Settings → Quality, MB/min):

| Quality            | Min | Preferred | Max |
| ------------------ | --- | --------- | --- |
| WEBDL/WEBRip-1080p | 0   | 15        | 100 |
| Bluray-1080p       | 0   | 30        | 150 |

## Release Preference: usenet first, YTS torrent fallback

The goal is small, good-quality 1080p — usenet when available, otherwise YTS/YIFY torrents (NOT big scene WEB-DLs).

**Delay profile** (Settings → Profiles → Delay):

- Preferred protocol: **Usenet**
- Usenet delay: **0** — grab usenet the moment it's found
- Torrent delay: **60 min** — hold torrents an hour so usenet gets first shot; YTS only grabbed if usenet never appears

## Custom Formats (TRaSH + YTS)

Scored in the HD-1080p profile:

| Format                            | Score  | Why                                  |
| --------------------------------- | ------ | ------------------------------------ |
| YTS                               | +150   | prefer YTS/YIFY among torrents       |
| x265 (HD)                         | +100   | HEVC — ~half the size at 1080p       |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 | auto-replace broken releases         |
| BR-DISK / Upscaled / Extras       | -10000 | block genuine junk                   |
| LQ / LQ (Release Title)           | **0**  | TRaSH bans YTS here — kept OFF on purpose |

> The `LQ` formats are TRaSH's "low quality groups" list, which includes YTS/YIFY.
> They are deliberately scored 0 (not -10000) so YTS is allowed. Do NOT re-enable
> LQ scoring or set min format score negative — it will block all YTS releases.

`YTS` is a custom ReleaseTitle format matching `\b(YTS|YIFY)\b`. Other imported TRaSH formats (tiers, streaming services) remain at 0.

## Indexers

Synced from Prowlarr (Full Sync) — do not edit indexers in Radarr, changes are overwritten every sync (see `apps/prowlarr/README.md`).

## Download Clients

| Client      | Host           | Category |
| ----------- | -------------- | -------- |
| qBittorrent | `gluetun:8085` | `radarr` |
| SABnzbd     | `sabnzbd:8080` | `movies` |
