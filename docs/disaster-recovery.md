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

- **Schedule**: Daily at 4am CT
- **Source**: `~/data/` + `~/.sops/`
- **Destination**: `~/backup/borg/` (NFS from NAS)
- **Retention**: 30 daily, 12 weekly, 12 monthly
- **Integrity checks**: Weekly repo + archive verification (last 3 archives)
- **Notifications**: ntfy on success/failure + uptime-kuma dead man's switch

### Per-App Borgmatic (DB Backups)

Each database app (Postgres and SQLite) has its own borgmatic instance backing up to a dedicated borg repo. Staggered schedules prevent resource contention.

| App                | Schedule | Borg Repo                         |
| ------------------ | -------- | --------------------------------- |
| miniflux           | 1:00 AM  | `~/data/miniflux/borg/`           |
| plausible          | 1:15 AM  | `~/data/plausible/borg/`          |
| zipline            | 1:30 AM  | `~/data/zipline/borg/`            |
| glitchtip          | 1:45 AM  | `~/data/glitchtip/borg/`          |
| bitmagnet          | 2:00 AM  | `~/data/bitmagnet/borg/`          |
| hello-world        | 2:15 AM  | `~/data/hello-world/borg/`        |
| paperless          | 2:30 AM  | `~/data/paperless/borg/`          |
| gitea              | 2:45 AM  | `~/data/gitea/borg/`              |
| close-powerlifting | 2:50 AM  | `~/data/close-powerlifting/borg/` |
| bang               | 2:55 AM  | `~/data/bang/borg/`               |
| gains              | 3:00 AM  | `~/data/gains/borg/`              |
| mm2us              | 3:05 AM  | `~/data/mm2us/borg/`              |
| notify             | 3:10 AM  | `~/data/notify/borg/`             |
| calendar           | 3:15 AM  | `~/data/calendar/borg/`           |
| favicon            | 3:20 AM  | `~/data/favicon/borg/`            |
| screenshot         | 3:25 AM  | `~/data/screenshot/borg/`         |
| **global**         | 4:00 AM  | `~/backup/borg/`                  |

Postgres apps: per-app borgmatic uses `postgresql_databases` hook to run pg_dump and archive the dump directly.
SQLite apps: per-app borgmatic uses `sqlite_databases` hook to do proper `sqlite3 .backup` before archiving.
All per-app repos store encrypted, deduplicated archives in `~/data/<app>/borg/` (local disk). Global borgmatic backs up all of `~/data/` (which includes per-app borg repos) to NFS as belt-and-suspenders.

### List Archives

```bash
docker compose -f ~/home-ops/apps/borgmatic/docker-compose.yml exec borgmatic borgmatic list
```

### Extract Full Archive

```bash
# List archives first
docker compose -f ~/home-ops/apps/borgmatic/docker-compose.yml exec borgmatic borgmatic list

# Extract latest archive to /restore
docker compose -f ~/home-ops/apps/borgmatic/docker-compose.yml exec borgmatic borgmatic extract --archive latest --destination /restore
```

### Extract Specific Files

```bash
docker compose -f ~/home-ops/apps/borgmatic/docker-compose.yml exec borgmatic borgmatic extract \
  --archive latest --destination /restore --path source/data/gitea
```

### Manual Backup

```bash
docker compose -f ~/home-ops/apps/borgmatic/docker-compose.yml exec borgmatic borgmatic create --verbosity 1
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
