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
| WEBDL/WEBRip-1080p | 0   | 15        | 40  |
| Bluray-1080p       | 0   | 30        | 40  |

> **Max is a hard cap, not a preference.** It was 100/150 — too loose: a 2h movie
> could still grab at 12–18GB and "pass", and usenet-first would take that big copy
> over a small YTS torrent. **40 MB/min** caps a 2h movie at ~4.8GB; YTS (~2GB)
> sails through, 8–17GB bloat is rejected outright. Lower this further to shrink
> more aggressively. Tradeoff: a movie only available large won't grab until a
> smaller release appears.

## Release Preference: usenet first, YTS torrent fallback

The goal is small, good-quality 1080p — usenet when available, otherwise YTS/YIFY torrents (NOT big scene WEB-DLs).

**Delay profile** (Settings → Profiles → Delay):

- Preferred protocol: **Usenet**
- Usenet delay: **0** — grab usenet the moment it's found
- Torrent delay: **60 min** — hold torrents an hour so usenet gets first shot; YTS only grabbed if usenet never appears

## Custom Formats (TRaSH + YTS)

Scored in the HD-1080p profile:

| Format                            | Score  | Why                                       |
| --------------------------------- | ------ | ----------------------------------------- |
| YTS                               | +150   | prefer YTS/YIFY among torrents            |
| x265 (HD)                         | +100   | HEVC — ~half the size at 1080p            |
| Repack/Proper / Repack2 / Repack3 | +5/6/7 | auto-replace broken releases              |
| BR-DISK / Upscaled / Extras       | -10000 | block genuine junk                        |
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

## Shrinking oversized existing files

Radarr **never auto-downgrades** — a 40GB Remux or fat Bluray stays forever, even
though it exceeds the size cap, because Radarr treats it as equal/higher quality.
The only way to shrink is delete-the-file → re-search.

Safe method (no permanent gaps): only delete a file once a clean small replacement
is confirmed grabbable. The leftover worklist is `redownload-list.md` (repo root,
gitignored).

Per movie:

1. Interactive search; find an allowed-quality (1080p WEB/Bluray) release whose
   only rejection reasons are existing-file ones (`existing meets cutoff`,
   `equal or higher preference`) — those vanish once the file is gone. Skip if the
   release also fails on size/seeders/subs.
2. Delete the movie file, trigger `MoviesSearch`. The new file imports under the
   40 MB/min cap + usenet-first/YTS rules.
3. Some grabs fail repeatedly (bad usenet articles) — re-search or leave for RSS.

Gotcha: clearing the queue with `blocklist=true` blocklists those exact releases —
only do it for the bad/big ones, not in-progress good downloads.
