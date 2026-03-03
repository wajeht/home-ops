# Disaster Recovery

How to recreate the homelab from scratch.

## What's Backed Up Where

| Data                  | Location                | Backup Strategy                   |
| --------------------- | ----------------------- | --------------------------------- |
| App configs/databases | `~/data/`               | Borgmatic → NAS (`~/backup/borg`) |
| SOPS age key          | `~/.sops/age-key.txt`   | Borgmatic → NAS                   |
| Docker auth           | `~/.docker/config.json` | Recreatable via `docker login`    |
| Secrets               | .env.sops files         | Encrypted in git                  |
| Media files           | `~/plex/` (NFS)         | NAS handles redundancy            |
| Immich photos         | `~/immich/` (NFS)       | NAS handles redundancy            |
| Compose files         | Git repo                | Already backed up                 |

## Critical Files

```bash
# These MUST be backed up - can't recreate without them
~/.sops/age-key.txt      # Decrypts all .env.sops secrets
~/data/                  # All app configs and databases
```

## Borgmatic Backups

Automated daily backups via borgmatic (borg wrapper). Encrypted, deduplicated, compressed (zstd).

### Global Borgmatic

- **Schedule**: Daily at 2:30am CT (after all per-app backups)
- **Source**: `~/data/` + `~/.sops/`
- **Destination**: `~/backup/borg/` (NFS from NAS)
- **Retention**: 7 daily, 4 weekly, 6 monthly
- **Integrity checks**: Weekly repo + archive verification (last 3 archives)
- **Notifications**: ntfy on success/failure + uptime-kuma dead man's switch

### Per-App Borgmatic

Each app with important data has its own borgmatic instance backing up DB + files to a dedicated borg repo. Staggered schedules prevent resource contention.

Apps with databases use `postgresql_databases` or `sqlite_databases` hooks for consistent DB snapshots. All apps also back up their full `~/data/<app>/` directory (excluding borgmatic state and raw DB files already handled by hooks).

All per-app borg repos are stored on NFS (`~/backup/<app>/`) so backups survive local disk failure. Global borgmatic also backs up `~/data/` to NFS as an additional safety net.

| App                | Schedule | Type          | Borg Repo                      |
| ------------------ | -------- | ------------- | ------------------------------ |
| gitea              | Hourly   | SQLite+files  | `~/backup/gitea/`              |
| vaultwarden        | Hourly   | SQLite+files  | `~/backup/vaultwarden/`        |
| miniflux           | 12:00 AM | Postgres (DB) | `~/backup/miniflux/`           |
| plausible          | 12:05 AM | PG + files    | `~/backup/plausible/`          |
| zipline            | 12:10 AM | PG + files    | `~/backup/zipline/`            |
| glitchtip          | 12:15 AM | PG + files    | `~/backup/glitchtip/`          |
| bitmagnet          | 12:20 AM | Postgres (DB) | `~/backup/bitmagnet/`          |
| hello-world        | 12:25 AM | Postgres (DB) | `~/backup/hello-world/`        |
| paperless          | 12:30 AM | PG + files    | `~/backup/paperless/`          |
| immich             | 12:35 AM | Postgres (DB) | `~/backup/immich/`             |
| uptime-kuma        | 12:40 AM | SQLite+files  | `~/backup/uptime-kuma/`        |
| authelia           | 12:45 AM | SQLite+files  | `~/backup/authelia/`           |
| sonarr             | 12:50 AM | SQLite+files  | `~/backup/sonarr/`             |
| radarr             | 12:55 AM | SQLite+files  | `~/backup/radarr/`             |
| prowlarr           | 1:00 AM  | SQLite+files  | `~/backup/prowlarr/`           |
| tautulli           | 1:05 AM  | SQLite+files  | `~/backup/tautulli/`           |
| audiobookshelf     | 1:10 AM  | SQLite+files  | `~/backup/audiobookshelf/`     |
| changedetection    | 1:15 AM  | Files only    | `~/backup/changedetection/`    |
| ntfy               | 1:20 AM  | SQLite+files  | `~/backup/ntfy/`               |
| close-powerlifting | 1:25 AM  | SQLite (DB)   | `~/backup/close-powerlifting/` |
| bang               | 1:30 AM  | SQLite (DB)   | `~/backup/bang/`               |
| favicon            | 1:35 AM  | SQLite+files  | `~/backup/favicon/`            |
| mm2us              | 1:40 AM  | SQLite (DB)   | `~/backup/mm2us/`              |
| notify             | 1:45 AM  | SQLite (DB)   | `~/backup/notify/`             |
| calendar           | 1:50 AM  | SQLite (DB)   | `~/backup/calendar/`           |
| screenshot         | 1:55 AM  | SQLite+files  | `~/backup/screenshot/`         |
| gains              | 2:00 AM  | SQLite (DB)   | `~/backup/gains/`              |
| **global**         | 2:30 AM  | All ~/data/   | `~/backup/borg/`               |

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

# Init single borg repo
docker exec <app>-borgmatic borgmatic init --encryption repokey-blake2
```

### How Restore Works

`borgmatic restore` restores **databases only** (via pg_restore/sqlite3). `borgmatic extract` extracts **files only**. For apps with both DB + files, you need both commands.

### Restore: DB-Only App (e.g. miniflux, gains)

```bash
# 1. Restore DB from latest archive
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
docker exec <app>-borgmatic borgmatic extract --archive latest --destination /

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
docker exec <app>-borgmatic borgmatic extract --archive latest --destination /

# 3. Start the app
docker start <app>
```

### Restore: Specific Files

```bash
# Extract a specific subdirectory
docker exec <app>-borgmatic borgmatic extract --archive latest --destination / --path source/data/uploads

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

### 3. Mount NFS (for media)

```bash
./scripts/home-ops.sh nfs mount
```

### 4. Initialize Borgmatic

After docker-cd deploys all apps, init borg repos and run first backup:

```bash
make borgmatic-init
make borgmatic-backup
```

### 5. Verify

```bash
./scripts/home-ops.sh status
```

## Testing Recovery

Periodically test by:

1. Spin up a test VM
2. Follow recovery steps
3. Verify services come up with data intact
