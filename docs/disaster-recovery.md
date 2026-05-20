# Disaster Recovery

How to recreate the homelab from scratch.

> **Migration notice (2026-05-20):** Per-app backups are slowly being migrated from `borgmatic` sidecars to centralized [Backrest](backrest.md) (restic web UI). The borgmatic schedule below is still authoritative for apps that have not yet been moved; once migrated, an app's row should be removed from this doc and the new home is [docs/backrest.md](backrest.md). See [Migration Status](backrest.md#migration-status) for current progress.

## What's Backed Up Where

| Data                  | Location                | Backup Strategy                |
| --------------------- | ----------------------- | ------------------------------ |
| App configs/databases | `~/data/`               | Borgmatic → NAS                |
| SOPS age key          | `~/.sops/age-key.txt`   | Borgmatic → NAS                |
| Docker auth           | `~/.docker/config.json` | Recreatable via `docker login` |
| Secrets               | .env.sops files         | Encrypted in git               |
| Media files           | `~/plex/` (NFS)         | NAS handles redundancy         |
| Immich photos         | `~/immich/` (NFS)       | NAS handles redundancy         |
| Compose files         | Git repo                | Already backed up              |

## Critical Files

```bash
# These MUST be backed up - can't recreate without them
~/.sops/age-key.txt      # Decrypts all .env.sops secrets
~/data/                  # All app configs and databases
```

## Borgmatic Backups

Automated daily backups via borgmatic (borg wrapper). Encrypted, deduplicated, compressed (zstd).

### Global Borgmatic

- **Schedule**: Daily at 3:45am CT (after all per-app backups)
- **Source**: `~/data/` + `~/.sops/`
- **Destination**: `~/backup/borg/` (NFS from NAS)
- **Retention**: 7 daily, 4 weekly, 6 monthly
- **Integrity checks**: Weekly repo + archive verification (last 3 archives)
- **Notifications**: ntfy on success/failure + uptime-kuma dead man's switch

### Per-App Borgmatic

Each app with important data has its own borgmatic instance backing up DB + files to NAS via NFS. Staggered schedules prevent resource contention.

Apps with databases use `postgresql_databases` or `sqlite_databases` hooks for consistent DB snapshots. All apps also back up their full `~/data/<app>/` directory (excluding borgmatic state and raw DB files already handled by hooks).

Each per-app borgmatic backs up to:

- **NAS** (`~/backup/<app>/` via NFS) — survives local disk failure

Global borgmatic also backs up `~/data/` to NFS as an additional safety net.

| App             | Schedule | Type          | Repo                        |
| --------------- | -------- | ------------- | --------------------------- |
| miniflux        | 12:00 AM | Postgres (DB) | `~/backup/miniflux/`        |
| plausible       | 12:05 AM | PG + files    | `~/backup/plausible/`       |
| zipline         | 12:10 AM | PG + files    | `~/backup/zipline/`         |
| glitchtip       | 12:15 AM | PG + files    | `~/backup/glitchtip/`       |
| bitmagnet       | 12:20 AM | Postgres (DB) | `~/backup/bitmagnet/`       |
| hello-world     | 12:25 AM | Postgres (DB) | `~/backup/hello-world/`     |
| paperless       | 12:30 AM | PG + files    | `~/backup/paperless/`       |
| immich          | 12:35 AM | Postgres (DB) | `~/backup/immich/`          |
| uptime-kuma     | 12:40 AM | SQLite+files  | `~/backup/uptime-kuma/`     |
| authelia        | 12:45 AM | SQLite+files  | `~/backup/authelia/`        |
| sonarr          | 12:50 AM | SQLite+files  | `~/backup/sonarr/`          |
| radarr          | 12:55 AM | SQLite+files  | `~/backup/radarr/`          |
| prowlarr        | 1:00 AM  | SQLite+files  | `~/backup/prowlarr/`        |
| tautulli        | 1:05 AM  | SQLite+files  | `~/backup/tautulli/`        |
| audiobookshelf  | 1:10 AM  | SQLite+files  | `~/backup/audiobookshelf/`  |
| changedetection | 1:15 AM  | Files only    | `~/backup/changedetection/` |
| notify          | 1:45 AM  | SQLite (DB)   | `~/backup/notify/`          |
| homeassistant   | 2:05 AM  | SQLite+files  | `~/backup/homeassistant/`   |
| zigbee2mqtt     | 2:10 AM  | Files only    | `~/backup/zigbee2mqtt/`     |
| garage          | 2:30 AM  | Files only    | `~/backup/garage/`          |
| dbgate          | 2:15 AM  | Files only    | `~/backup/dbgate/`          |
| frigate         | 2:20 AM  | SQLite+files  | `~/backup/frigate/`         |
| listenarr       | 2:25 AM  | SQLite+files  | `~/backup/listenarr/`       |
| traefik         | 2:40 AM  | Files only    | `~/backup/traefik/`         |
| plex            | 2:45 AM  | SQLite+files  | `~/backup/plex/`            |
| seerr           | 2:50 AM  | SQLite+files  | `~/backup/seerr/`           |
| bazarr          | 2:55 AM  | SQLite+files  | `~/backup/bazarr/`          |
| sabnzbd         | 3:00 AM  | SQLite+files  | `~/backup/sabnzbd/`         |
| vpn-qbit        | 3:05 AM  | Files only    | `~/backup/vpn-qbit/`        |
| nut             | 3:10 AM  | Files only    | `~/backup/nut/`             |
| vaultwarden     | 3:15 AM  | SQLite+files  | `~/backup/vaultwarden/`     |
| gitea           | 3:20 AM  | SQLite+files  | `~/backup/gitea/`           |
| **global**      | 3:45 AM  | All ~/data/   | `~/backup/borg/`            |

### Borgmatic Commands

```bash
# Init all borg repos (first time setup, skips existing)
make borgmatic-init

# Run backup on all borgmatic containers
make borgmatic-backup

# Manual backup (single app)
docker exec <app>-borgmatic borgmatic create --verbosity 1

# List archives
docker exec <app>-borgmatic borgmatic list

# List archive contents
docker exec <app>-borgmatic borg list /repository::<archive-name>

# Init single borg repo (borgmatic 2.x syntax)
docker exec <app>-borgmatic borgmatic repo-create --encryption repokey-blake2
```

### How Restore Works

`borgmatic restore` restores **databases only** (via pg_restore/sqlite3). `borgmatic extract` extracts **files only**. For apps with both DB + files, you need both commands.

### Restore: DB-Only App (e.g. miniflux, gains)

```bash
# Restore DB from latest archive
docker exec <app>-borgmatic borgmatic restore --archive latest

# Or from a specific archive
docker exec <app>-borgmatic borgmatic restore --archive <archive-name>
```

That's it — no files to extract.

### Restore: DB + Files App (e.g. zipline, vaultwarden)

```bash
# 1. Stop the app (not borgmatic)
docker stop <app>

# 2. Extract files to data dir
docker exec <app>-borgmatic borgmatic extract --archive latest --destination / --archive latest

# 3. Restore DB
docker exec <app>-borgmatic borgmatic restore --archive latest

# 4. Start the app
docker start <app>
```

Files extract to `/source/data/` inside the container which maps to `~/data/<app>/`. The `--destination /` makes paths resolve correctly since archives store files as `source/data/...`.

### Restore: Files-Only App (e.g. changedetection)

```bash
# 1. Stop the app
docker stop <app>

# 2. Extract files
docker exec <app>-borgmatic borgmatic extract --archive latest --destination / --archive latest

# 3. Start the app
docker start <app>
```

### Restore: Specific Files

```bash
# Extract a specific subdirectory
docker exec <app>-borgmatic borgmatic extract --archive latest --destination / --path source/data/uploads --archive latest

# List archive contents first to find paths
docker exec <app>-borgmatic borg list /repository::<archive-name>
```

### Global Borgmatic

Belt-and-suspenders backup of all `~/data/` + `~/.sops/`. Use per-app borgmatic for restores when possible (includes proper DB dumps). Fall back to global for file-level recovery.

```bash
# Manual backup
docker exec borgmatic borgmatic create --verbosity 1

# List archives
docker exec borgmatic borgmatic list

# Extract specific app's files
docker exec borgmatic borgmatic extract --archive latest --destination /restore --path source/data/gitea

# Extract everything
docker exec borgmatic borgmatic extract --archive latest --destination /restore
```

**Note:** Global borgmatic does NOT have DB hooks — it backs up raw DB files. For consistent DB restores, always prefer per-app borgmatic.

## Recovery Steps

### 1. Restore Critical Files

If borg repo is accessible (NAS intact):

```bash
# Mount NFS backup share
./scripts/home-ops.sh nfs mount backup

# Extract latest borgmatic archive
docker run --rm -e BORG_PASSPHRASE='<passphrase>' \
  -v ~/backup/borg:/repository:ro \
  -v ~/data:/restore/data \
  -v ~/.sops:/restore/sops \
  ghcr.io/borgmatic-collective/borgmatic \
  borgmatic extract --archive latest --destination /restore
```

If borg repo is NOT accessible, restore from wherever you have a copy of `~/data/` and `~/.sops/`.

### 2. Run Install

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
cd ~/home-ops && ./scripts/home-ops.sh install
```

The install script handles everything: Docker, SOPS, networks, and docker-cd deployment.

### 3. Mount NFS and SATA

```bash
./scripts/home-ops.sh nfs mount
./scripts/home-ops.sh nfs persist      # survive reboots
./scripts/home-ops.sh sata persist     # survive reboots
```

### 4. Initialize Borgmatic

After docker-cd deploys all apps, init borg repos and run first backup:

```bash
make borgmatic-init
make borgmatic-backup
```

### 5. OS Tuning

See [Quick Start — OS Tuning](quick-start.md#os-tuning) for swappiness and CPU governor settings.

### 6. Verify

```bash
./scripts/home-ops.sh status
```

## After Hardware Migration / Full Redeploy

When swapping hardware (e.g. new gateway) or deleting docker-cd state to force a full redeploy, several things break. Here's the checklist:

### 1. NFS Mounts (fix FIRST)

NFS mounts drop on reboot/network change. If docker-cd deploys before NFS is mounted, containers see empty dirs instead of NAS data.

```bash
make nfs-mount
make nfs-persist
```

**Must be done before restarting any containers**, otherwise:

- Immich sees empty upload dir, fails mount checks
- Global borgmatic sees empty repo, `borgmatic repo-create` tries to create a new one
- Per-app borgmatic can't reach NAS repos

### 2. SATA Mount

```bash
make sata-mount
make sata-persist
```

### 3. Immich Upload Markers

Immich v2.6+ checks `.immich` marker files in upload subdirs on startup. After a fresh deploy these don't exist yet:

```bash
cd ~/immich/upload
mkdir -p thumbs upload backups library profile encoded-video
for d in thumbs upload backups library profile encoded-video; do touch $d/.immich; done
docker restart immich
```

### 4. Stale Borg Locks

Containers that were running when the redeploy happened may leave stale lock files:

```bash
docker exec <app>-borgmatic borg break-lock /repository
```

### 5. Container Permission Issues

After a fresh deploy, some containers crash with `EACCES: permission denied` because `cap_drop: ALL` removes filesystem caps. If a container needs to write to its data dir, it needs caps:

```bash
# Check logs for EACCES errors
docker logs <container> --tail 20

# Fix: add cap_add to docker-compose.yml (most apps need these)
cap_add:
  - CHOWN
  - DAC_OVERRIDE
  - FOWNER
  - SETGID
  - SETUID
```

### 6. External Network Dependencies

dbgate and similar apps depend on other stacks' internal networks (e.g. `miniflux_miniflux-internal`). If those stacks haven't deployed yet, the dependent stack fails. docker-cd retries, so just wait or trigger another sync after all stacks are up.

### 7. Borgmatic Init

After everything is up and NFS is mounted:

```bash
make borgmatic-init
make borgmatic-backup    # optional: run first backup immediately
```

## Testing Recovery

Periodically test by:

1. Spin up a test VM
2. Follow recovery steps
3. Verify services come up with data intact
