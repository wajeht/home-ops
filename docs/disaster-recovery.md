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

- **Schedule**: Daily at 4:30am CT
- **Source**: `~/data/` + `~/.sops/`
- **Destination**: `~/backup/borg/` (NFS from NAS)
- **Retention**: 7 daily, 4 weekly, 6 monthly
- **Integrity checks**: Weekly repo + archive verification (last 3 archives)
- **Notifications**: ntfy on success/failure + uptime-kuma dead man's switch

### Per-App Borgmatic

Each app with important data has its own borgmatic instance backing up DB + files to a dedicated borg repo. Staggered schedules prevent resource contention.

Apps with databases use `postgresql_databases` or `sqlite_databases` hooks for consistent DB snapshots. All apps also back up their full `~/data/<app>/` directory (excluding borg/borgmatic state and raw DB files already handled by hooks).

| App                | Schedule | Type          | Borg Repo                         |
| ------------------ | -------- | ------------- | --------------------------------- |
| miniflux           | 1:00 AM  | Postgres (DB) | `~/data/miniflux/borg/`           |
| plausible          | 1:15 AM  | PG + files    | `~/data/plausible/borg/`          |
| zipline            | 1:30 AM  | PG + files    | `~/data/zipline/borg/`            |
| glitchtip          | 1:45 AM  | PG + files    | `~/data/glitchtip/borg/`          |
| bitmagnet          | 2:00 AM  | Postgres (DB) | `~/data/bitmagnet/borg/`          |
| hello-world        | 2:15 AM  | Postgres (DB) | `~/data/hello-world/borg/`        |
| paperless          | 2:30 AM  | PG + files    | `~/data/paperless/borg/`          |
| gitea              | 2:45 AM  | SQLite+files  | `~/data/gitea/borg/`              |
| close-powerlifting | 2:50 AM  | SQLite (DB)   | `~/data/close-powerlifting/borg/` |
| bang               | 2:55 AM  | SQLite (DB)   | `~/data/bang/borg/`               |
| gains              | 3:00 AM  | SQLite (DB)   | `~/data/gains/borg/`              |
| mm2us              | 3:05 AM  | SQLite (DB)   | `~/data/mm2us/borg/`              |
| notify             | 3:10 AM  | SQLite (DB)   | `~/data/notify/borg/`             |
| calendar           | 3:15 AM  | SQLite (DB)   | `~/data/calendar/borg/`           |
| favicon            | 3:20 AM  | SQLite+files  | `~/data/favicon/borg/`            |
| screenshot         | 3:25 AM  | SQLite+files  | `~/data/screenshot/borg/`         |
| vaultwarden        | 3:30 AM  | SQLite+files  | `~/data/vaultwarden/borg/`        |
| uptime-kuma        | 3:35 AM  | SQLite+files  | `~/data/uptime-kuma/borg/`        |
| authelia           | 3:40 AM  | SQLite+files  | `~/data/authelia/borg/`           |
| sonarr             | 3:45 AM  | SQLite+files  | `~/data/sonarr/borg/`             |
| radarr             | 3:50 AM  | SQLite+files  | `~/data/radarr/borg/`             |
| prowlarr           | 3:55 AM  | SQLite+files  | `~/data/prowlarr/borg/`           |
| tautulli           | 4:00 AM  | SQLite+files  | `~/data/tautulli/borg/`           |
| audiobookshelf     | 4:05 AM  | SQLite+files  | `~/data/audiobookshelf/borg/`     |
| changedetection    | 4:10 AM  | Files only    | `~/data/changedetection/borg/`    |
| ntfy               | 4:15 AM  | SQLite+files  | `~/data/ntfy/borg/`               |
| **global**         | 4:30 AM  | All ~/data/   | `~/backup/borg/`                  |

All per-app repos store encrypted, deduplicated archives in `~/data/<app>/borg/` (local disk). Global borgmatic backs up all of `~/data/` (which includes per-app borg repos) to NFS as belt-and-suspenders.

### Per-App Borgmatic Commands

```bash
# Manual backup
docker exec <app>-borgmatic borgmatic create --verbosity 1

# List archives
docker exec <app>-borgmatic borgmatic list

# List archive contents
docker exec <app>-borgmatic borg list /repository::<archive-name>

# Restore database (Postgres or SQLite) from latest archive
docker exec <app>-borgmatic borgmatic restore --archive latest

# Restore database from specific archive
docker exec <app>-borgmatic borgmatic restore --archive <archive-name>

# Extract files from archive
docker exec <app>-borgmatic borgmatic extract --archive latest --destination /restore

# Extract specific path
docker exec <app>-borgmatic borgmatic extract --archive latest --destination /restore --path source/data/<subdir>
```

### Global Borgmatic Commands

```bash
# Manual backup
docker exec borgmatic borgmatic create --verbosity 1

# List archives
docker exec borgmatic borgmatic list

# Extract full archive
docker exec borgmatic borgmatic extract --archive latest --destination /restore

# Extract specific app's files
docker exec borgmatic borgmatic extract --archive latest --destination /restore --path source/data/gitea
```

### Initialize New Borg Repo

Required when adding borgmatic to an app for the first time:

```bash
docker exec <app>-borgmatic borgmatic init --encryption repokey-blake2
```

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

### 4. Verify

```bash
./scripts/home-ops.sh status
```

## Testing Recovery

Periodically test by:

1. Spin up a test VM
2. Follow recovery steps
3. Verify services come up with data intact
