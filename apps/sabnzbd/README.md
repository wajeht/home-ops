# SABnzbd

Usenet client for Sonarr/Radarr. Runtime config in `~/data/sabnzbd/sabnzbd.ini` (not GitOps).

## Performance

Usenet at high speed is CPU-bound (SSL decrypt) + benefits from a large article cache.

Container limits (`docker-compose.yml`): `cpus: 3.0`, `memory: 1G` (were 1.0 / 512M — capped at ~1 core).

Runtime (`sabnzbd.ini`, via API `mode=set_config` or UI):

| Setting                 | Value |
| ----------------------- | ----- |
| `cache_limit`           | 384M  |
| `downloader_sleep_time` | 0     |
| `direct_unpack`         | 1     |

Result ~60–70 MB/s on 2+ cores. Don't raise `cache_limit` without raising container `memory` (mem runs ~80% of 1G), or SAB gets OOM-killed.

Server: Newshosting, 50 connections, SSL. Categories: `movies`, `tv`, `prowlarr`.
