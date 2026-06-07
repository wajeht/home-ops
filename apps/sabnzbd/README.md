# SABnzbd

Usenet download client for Sonarr/Radarr. Config lives in `~/data/sabnzbd/sabnzbd.ini` (runtime, not GitOps).

## Performance

Usenet at high speed is **CPU-bound** (SSL decryption) and benefits from a large
article cache. The defaults (1 CPU / 512M) capped throughput at ~1 core.

Container limits (`docker-compose.yml`):

| Resource | Value | Why                                                      |
| -------- | ----- | -------------------------------------------------------- |
| cpus     | 3.0   | SSL decode spreads across cores — the main speed limiter |
| memory   | 1G    | room for the article cache below                         |

Runtime tuning (`sabnzbd.ini` → Config → General, or via API `mode=set_config`):

| Setting                 | Value | Why                                                                                                |
| ----------------------- | ----- | -------------------------------------------------------------------------------------------------- |
| `cache_limit`           | 384M  | larger article cache = smoother sustained speed; kept under the 1G container cap to avoid OOM-kill |
| `downloader_sleep_time` | 0     | no artificial throttle (was 10) — fine with spare cores                                            |
| `direct_unpack`         | 1     | unpack while downloading                                                                           |

Result: ~60–70 MB/s using 2+ cores, vs ~1-core-capped before.

> Memory runs ~80% of 1G with the 384M cache. Don't raise `cache_limit` without
> also raising the container `memory` limit, or SAB gets OOM-killed.

Server: Newshosting, 50 connections, SSL. Categories: `movies`, `tv`, `prowlarr`.
