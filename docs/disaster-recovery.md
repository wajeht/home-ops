# Disaster Recovery

How to back up, restore, and recreate the homelab from scratch.

Backups run through [Backrest](https://github.com/garethgeorge/backrest), a web UI over [restic](https://restic.net). One container manages per-app restic repos, restores, and ntfy notifications.

## Start Here

- New app backup: [Adding an App](#adding-an-app)
- Manual backup: [Backup Commands](#backup-commands)
- Restore one app: [Restore](#restore)
- Ad-hoc SQL dump/restore: [dcdb](#ad-hoc-dumps--restores-with-dcdb)
- Full rebuild: [Full Rebuild](#full-rebuild)
- Backrest operations: [Operations](#operations)

## What's Backed Up Where

| Data                  | Location                | Backup Strategy                                          |
| --------------------- | ----------------------- | -------------------------------------------------------- |
| App configs/databases | `~/data/`               | Per-app Backrest plan → NAS (`~/backup/restic/<app>/`)   |
| SOPS age key          | `~/.sops/age-key.txt`   | Backrest `global` plan → NAS (`~/backup/restic/global/`) |
| All `~/data/` raw     | `~/data/`               | Backrest `global` plan                                   |
| Docker auth           | `~/.docker/config.json` | Recreatable via `docker login`                           |
| Secrets               | `.env.sops` files       | Encrypted in git                                         |
| Media files           | `~/plex/` on NFS        | NAS handles redundancy                                   |
| Immich photos         | `~/immich/` on NFS      | NAS handles redundancy                                   |
| Compose files         | Git repo                | Already backed up                                        |

## Critical Files

```bash
# These MUST be backed up — can't recreate without them
~/.sops/age-key.txt           # Decrypts all .env.sops secrets and auth allowlists
~/data/                       # All app configs and databases
RESTIC_PASSWORD               # In apps/backrest/.env.sops — without it, NO restic repo is readable
```

`RESTIC_PASSWORD` is the master key for all backups. Without it, every restic repo is permanently unrecoverable. Keep it in your password manager. The age key is its only counterpart on the secrets side.

## Architecture

```
apps/backrest/
├── docker-compose.yml      # Backrest service + x-docker-cd.rolling_update: false
├── config/
│   └── config.json         # repos + plans
└── .env.sops               # RESTIC_PASSWORD
```

- **Image:** `ghcr.io/wajeht/backrest` — custom build of upstream Backrest with `sqlite`, `postgresql-client`, `jq` baked in. Source: [wajeht/backrest](https://github.com/wajeht/backrest). Renovate **does not** auto-update `ghcr.io/wajeht/*` images — manually bump the digest when a new version is published.
- **Web UI:** `https://backrest.jaw.dev`, gated by `oauth2-admin@file`. Backrest's own auth is disabled.
- **Repos:** `/home/jaw/backup/restic/<app>/` — one restic repo per app + one `global`. All use the same shared `RESTIC_PASSWORD`.
- **Source data:** `/home/jaw/data/` mounted into Backrest as `/source/` read-write. Pre-backup hooks write dump files into per-app data dirs.
- **SOPS age key:** `/home/jaw/.sops/` mounted as `/sops/` read-only. Only the global plan reads this.
- **Docker socket:** mounted read-write so hooks can `docker exec` into app containers for `pg_dump`.
- **Resource limits:** 2 CPU / 4 GB memory. Restic's in-memory index can spike well past source data size on large backups — 1 GB caused repeated OOMs.

## Backup Schedule

Per-app schedules are staggered to prevent resource contention. `global` runs last after all per-app backups complete.

| App           | Schedule | Type                 | Notes                                                         |
| ------------- | -------- | -------------------- | ------------------------------------------------------------- |
| hello-world   | 12:00 AM | Postgres DB only     |                                                               |
| immich        | 12:10 AM | Postgres DB only     | Photos at `~/immich` on NFS are not backed up here            |
| gatus         | 12:20 AM | SQLite + files       | DB file is `gatus.db`                                         |
| radarr        | 12:30 AM | SQLite + files       | Excludes MediaCover, Backups, logs.db, asp, Sentry, \*.pid    |
| prowlarr      | 12:40 AM | SQLite + files       |                                                               |
| ntfy          | 12:50 AM | SQLite x2 + files    | Two DBs: `user.db` + `cache.db`                               |
| bang          | 1:00 AM  | SQLite DB only       | Ephemeral keinos/sqlite3 — bang has no `container_name`       |
| favicon       | 1:10 AM  | SQLite + files       |                                                               |
| mm2us         | 1:20 AM  | SQLite DB only       |                                                               |
| notify        | 1:30 AM  | SQLite DB only       |                                                               |
| calendar      | 1:40 AM  | SQLite DB only       |                                                               |
| screenshot    | 1:50 AM  | SQLite + files       |                                                               |
| gains         | 2:00 AM  | SQLite DB only       |                                                               |
| homeassistant | 2:10 AM  | SQLite + files       | DB file is `home-assistant_v2.db`                             |
| zigbee2mqtt   | 2:20 AM  | Files only           |                                                               |
| dbgate        | 2:30 AM  | Files only           | `/mnt/*` mounts to other apps' data NOT backed up here        |
| garage        | 2:40 AM  | Files only           | meta + data dirs                                              |
| beszel        | 2:50 AM  | SQLite + files       | DB file is `data.db`                                          |
| traefik       | 3:00 AM  | Files only           | Includes `acme.json` certs                                    |
| plex          | 3:10 AM  | SQLite x2 + files    | Two DBs deeply nested under `Library/Application Support/...` |
| seerr         | 3:20 AM  | SQLite + files       | DB at `db/db.sqlite3`                                         |
| bazarr        | 3:30 AM  | SQLite + files       | DB at `db/bazarr.db`                                          |
| sabnzbd       | 3:40 AM  | SQLite + files       | DB at `admin/history1.db`. Excludes Downloads                 |
| vpn-qbit      | 3:50 AM  | Files only           | Two source paths: qbittorrent + gluetun                       |
| vaultwarden   | 4:00 AM  | SQLite + files       | DB file is `db.sqlite3`                                       |
| gitea         | 4:10 AM  | SQLite + files       | DB at `gitea/gitea.db`. Includes all git repos                |
| cap           | 4:20 AM  | Redis RDB only       | `redis-cli SAVE` hook, then snapshot `dump.rdb`               |
| umami         | 4:30 AM  | Postgres DB only     | `pg_dump` via `docker exec umami-db`                          |
| miniflux      | 4:40 AM  | Postgres DB only     | `pg_dump` via `docker exec miniflux-db`                       |
| sonarr        | 4:50 AM  | SQLite + files       | Excludes MediaCover, Backups, logs.db, asp, Sentry, \*.pid    |
| yubal         | 5:00 AM  | SQLite + files       | Config only; downloaded music remains on the NAS              |
| **global**    | 5:10 AM  | All ~/data + ~/.sops | File-level only. Excludes `*.bak`, `*.dump`, backrest state   |

Retention is **7 daily / 4 weekly / 6 monthly** for every plan. Prune runs Sunday 6 AM, integrity check Sunday 7 AM — both after `global` (5:10 AM) finishes, so weekly maintenance never overlaps the daily backups.

## Adding an App

For each app, add **one repo + one plan** to `apps/backrest/config/config.json`. Commit + push — docker-cd restarts Backrest with the new config.

After pushing, verify the entries are still in `config.json` on the server. A formatter has stripped new JSON entries on some pushes.

### Repo Block

```json
{
  "id": "<app>",
  "uri": "/repos/<app>",
  "password": "",
  "autoInitialize": true,
  "prunePolicy": { "schedule": { "cron": "0 4 * * 0" }, "maxUnusedPercent": 10 },
  "checkPolicy": { "schedule": { "cron": "0 5 * * 0" }, "structureOnly": true }
}
```

- `password: ""` — falls back to the shared `RESTIC_PASSWORD` env var
- `autoInitialize: true` — creates the restic repo on first backup

### Plan: SQLite DB Only

```json
{
  "id": "<app>",
  "repo": "<app>",
  "paths": ["/source/<app>/.<app>.bak"],
  "schedule": { "cron": "30 1 * * *", "clock": "CLOCK_LOCAL" },
  "retention": { "policyTimeBucketed": { "daily": 7, "weekly": 4, "monthly": 6 } },
  "hooks": [
    {
      "conditions": ["CONDITION_SNAPSHOT_START"],
      "onError": "ON_ERROR_CANCEL",
      "actionCommand": {
        "command": "sqlite3 /source/<app>/db.sqlite -cmd \".timeout 30000\" \".backup /source/<app>/.<app>.bak\""
      }
    },
    {
      "conditions": ["CONDITION_SNAPSHOT_END"],
      "actionCommand": { "command": "rm -f /source/<app>/.<app>.bak" }
    }
  ]
}
```

The `.timeout 30000` handles lock contention for live DBs. Without it, sqlite3 fails immediately if another connection holds a lock.

### Plan: SQLite + Files

Same as DB-only, but `paths` is the whole data dir and excludes filter out raw DB files:

```json
{
  "paths": ["/source/<app>"],
  "excludes": ["**/<app>/<db-file>.db", "**/<app>/<db-file>.db-wal", "**/<app>/<db-file>.db-shm"]
}
```

### Plan: Postgres

Use `docker exec` into the app's `*-db` container so `pg_dump` matches the Postgres major version. Use `docker cp` to pull the dump out.

```json
{
  "hooks": [
    {
      "conditions": ["CONDITION_SNAPSHOT_START"],
      "onError": "ON_ERROR_CANCEL",
      "actionCommand": {
        "command": "docker exec <app>-db pg_dump -U <user> -d <dbname> -F custom -f /tmp/<app>.dump && docker cp <app>-db:/tmp/<app>.dump /source/<app>/.<app>.dump && docker exec <app>-db rm -f /tmp/<app>.dump"
      }
    },
    {
      "conditions": ["CONDITION_SNAPSHOT_END"],
      "actionCommand": { "command": "rm -f /source/<app>/.<app>.dump" }
    }
  ]
}
```

The app's `*-db` container needs `container_name: <app>-db` set.

### Plan: Files Only

```json
{
  "paths": ["/source/<app>"],
  "hooks": [
    /* only ntfy success/error hooks, no DB hooks */
  ]
}
```

### Plan: Multiple SQLite DBs

Chain the `sqlite3 .backup` calls with `&&`:

```json
{
  "actionCommand": {
    "command": "sqlite3 /source/ntfy/user.db -cmd \".timeout 30000\" \".backup /source/ntfy/.ntfy-user.bak\" && sqlite3 /source/ntfy/cache.db -cmd \".timeout 30000\" \".backup /source/ntfy/.ntfy-cache.bak\""
  }
}
```

Plex has spaces in its paths (`Library/Application Support/...`) — wrap each path argument in **single quotes** so the shell preserves them:

```json
"command": "sqlite3 '/source/plex/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db' -cmd '.timeout 30000' '.backup /source/plex/.plex-library.bak'"
```

### Plan: App Without `container_name`

If the app uses `x-docker-cd.rolling_update: true`, adding `container_name` breaks rolling updates because Docker can't have two containers with the same name during the swap. Use an ephemeral container instead:

```json
"command": "docker run --rm -v /home/jaw/data/bang:/data keinos/sqlite3:3.51.3@sha256:520cfebb116119cc642b72d72c3ff948cc120a891dc4d83824c664f1ca65a354 sqlite3 /data/db.sqlite \".backup /data/.bang.bak\""
```

Trade-offs: rolling updates preserved; cost is image pull on first run + extra exec overhead. Use only when needed.

### Notifications

ntfy uses Backrest's Shoutrrr action. Two hooks per plan: success and error.

```json
{
  "conditions": ["CONDITION_SNAPSHOT_SUCCESS"],
  "onError": "ON_ERROR_IGNORE",
  "actionShoutrrr": {
    "shoutrrrUrl": "ntfy://ntfy/borgmatic?scheme=http&title=<app>+backup+complete&priority=Min&tags=white_check_mark",
    "template": "<app> backup finished"
  }
}
```

URL params: `scheme=http`, `title=<URL-encoded>`, `priority=Min|Low|Default|High|Max`, `tags=<comma-separated>`. ntfy is reachable on the `traefik` network.

## Backup Commands

### Manual trigger

**Via UI:** `https://backrest.jaw.dev` → click plan → **Backup Now**.

**Via CLI:**

```bash
docker exec backrest restic -r /repos/<app> backup /source/<app>
```

### Inspect / manage

```bash
docker exec backrest restic -r /repos/<app> snapshots
docker exec backrest restic -r /repos/<app> stats
docker exec backrest restic -r /repos/<app> check
docker exec backrest restic -r /repos/<app> ls latest
docker exec backrest restic -r /repos/<app> forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

`RESTIC_PASSWORD` is already in the container's env, so no flag needed.

### Stale lock recovery

If a backup is killed mid-run, restic leaves a lock file in the repo. Subsequent operations fail with `unable to create lock in backend: repository is already locked by PID ...`.

```bash
docker exec backrest restic -r /repos/<app> unlock --remove-all
```

Plain `unlock` only removes non-exclusive locks. `--remove-all` clears exclusive locks too.

## Restore

Restoring = pick a snapshot → extract files → put them back. Backrest gives you the files; you handle the app-level swap.

### Via UI

1. `https://backrest.jaw.dev` → click plan → **Tree View**
2. Pick a snapshot → click **Restore**
3. Target path: `/tmp/restore` inside the Backrest container. On the host this is tmpfs, so copy out before restart.

### Via CLI

```bash
docker exec backrest restic -r /repos/<app> snapshots                      # list snapshots
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore
docker exec backrest restic -r /repos/<app> restore <id> --target /tmp/restore  # specific snapshot
```

### Restore: SQLite DB Only

```bash
# 1. Extract
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore

# 2. Stop the app
cd ~/home-ops/apps/bang && docker compose stop

# 3. Restore via sqlite3 .restore
docker exec backrest sqlite3 /source/bang/db.sqlite ".restore /tmp/restore/source/bang/.bang.bak"

# 4. Remove stale WAL/SHM
rm -f /home/jaw/data/bang/db.sqlite-wal /home/jaw/data/bang/db.sqlite-shm

# 5. Start the app
docker compose up -d
```

### Restore: SQLite + Files

```bash
# 1. Extract everything
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore

# 2. Stop the app
cd ~/home-ops/apps/<app> && docker compose stop

# 3. Restore files
rsync -a --delete /tmp/restore/source/<app>/ /home/jaw/data/<app>/ --exclude '.<app>.bak'

# 4. Restore DB via sqlite3 .restore
docker exec backrest sqlite3 /home/jaw/data/<app>/<db-file>.db ".restore /tmp/restore/source/<app>/.<app>.bak"

# 5. Remove stale WAL/SHM
rm -f /home/jaw/data/<app>/<db-file>.db-wal /home/jaw/data/<app>/<db-file>.db-shm

# 6. Start
docker compose up -d
```

### Restore: Postgres DB Only

```bash
# 1. Extract
docker exec backrest restic -r /repos/hello-world restore latest --target /tmp/restore

# 2. Bring DB container up
cd ~/home-ops/apps/hello-world && docker compose up -d hello-world-db

# 3. Drop + recreate the database
docker exec hello-world-db dropdb -U hello-world hello-world
docker exec hello-world-db createdb -U hello-world hello-world

# 4. Restore via pg_restore
docker cp /tmp/restore/source/hello-world/.hello-world.dump hello-world-db:/tmp/restore.dump
docker exec hello-world-db pg_restore -U hello-world -d hello-world /tmp/restore.dump
docker exec hello-world-db rm /tmp/restore.dump

# 5. Bring app up
docker compose up -d
```

### Restore: Files Only

```bash
# 1. Extract
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore

# 2. Stop
cd ~/home-ops/apps/<app> && docker compose stop

# 3. rsync files back
rsync -a --delete /tmp/restore/source/<app>/ /home/jaw/data/<app>/

# 4. Start
docker compose up -d
```

### Restore: Multiple DBs in One App

Same as single-DB but restore each DB in sequence. Example for ntfy:

```bash
docker exec backrest restic -r /repos/ntfy restore latest --target /tmp/restore
cd ~/home-ops/apps/ntfy && docker compose stop

rsync -a --delete /tmp/restore/source/ntfy/ /home/jaw/data/ntfy/ \
  --exclude '.ntfy-user.bak' --exclude '.ntfy-cache.bak'

docker exec backrest sqlite3 /home/jaw/data/ntfy/user.db ".restore /tmp/restore/source/ntfy/.ntfy-user.bak"
docker exec backrest sqlite3 /home/jaw/data/ntfy/cache.db ".restore /tmp/restore/source/ntfy/.ntfy-cache.bak"
rm -f /home/jaw/data/ntfy/user.db-wal /home/jaw/data/ntfy/user.db-shm
rm -f /home/jaw/data/ntfy/cache.db-wal /home/jaw/data/ntfy/cache.db-shm

docker compose up -d
```

### Restore: Specific files

```bash
docker exec backrest restic -r /repos/<app> ls latest | grep <pattern>
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore --include /source/<app>/<specific-path>
```

### Restore: SOPS age key

The `global` plan backs up `/sops/` to `/repos/global`. If the host's `~/.sops/age-key.txt` is lost but the restic repo + `RESTIC_PASSWORD` survive:

```bash
docker exec backrest restic -r /repos/global restore latest --target /tmp/restore --include /sops/age-key.txt
docker cp backrest:/tmp/restore/sops/age-key.txt /tmp/age-key.txt
mkdir -p ~/.sops && mv /tmp/age-key.txt ~/.sops/age-key.txt
chmod 600 ~/.sops/age-key.txt
```

Without `~/.sops/age-key.txt`, every `.env.sops` is unreadable. Recovery requires either the age key or plaintext copies of every secret and allowlist. Back up the age key to multiple locations.

### Test Restore Drill

```bash
# Pick a small repo
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore-test
docker exec backrest sqlite3 /tmp/restore-test/source/bang/.bang.bak ".tables"
```

If `.tables` lists bang's tables, the full pipeline (backup + restore) works end-to-end. The cheapest way to discover backup rot before you need it.

## Full Rebuild

### Scenarios

| Scenario                                         | Recovery                                                                                                                                                                       |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| One app's data lost, NAS intact                  | Restore that app from `/repos/<app>` using the per-app restore procedure above                                                                                                 |
| One app's DB corrupted but files OK              | Restore just the `.bak`/`.dump` via `--include`, then `sqlite3 .restore` or `pg_restore`                                                                                       |
| Backrest container gone, restic repos intact     | Spin restic up anywhere with the password: `docker run --rm -e RESTIC_PASSWORD=… -v /mnt/nas/backup/restic:/repos restic/restic:latest -r /repos/<app> snapshots`              |
| Backrest config.json corrupted                   | Restore from git (`apps/backrest/config/config.json`) — the source of truth                                                                                                    |
| Whole local server gone, NAS intact              | Restore `~/home-ops` from git → restore `~/.sops/age-key.txt` from your password manager → mount NFS → deploy Backrest → restore each app                                      |
| `RESTIC_PASSWORD` lost                           | **No recovery — every restic repo is permanently unreadable.** Keep this password in your password manager.                                                                    |
| SOPS age key lost AND not in Backrest repo       | Every `.env.sops` is unreadable. Restoring `.env` plaintext copies is the only path. This includes oauth2-proxy allowlists. Back up the age key to multiple offline locations. |
| Restic repo + age key + RESTIC_PASSWORD all lost | Full data loss for that app. Compose files in git still survive — apps can be redeployed empty, configs lost.                                                                  |

### Full Rebuild Procedure

#### 1. Restore Critical Files

If the NAS is intact:

```bash
# Mount NFS backup share
./scripts/setup.sh nfs mount backup

# Restore the global snapshot
docker run --rm -e RESTIC_PASSWORD='<from-password-manager>' \
  -v ~/backup/restic/global:/repository:ro \
  -v ~/data:/restore/data \
  -v ~/.sops:/restore/sops \
  restic/restic:0.18.1 \
  -r /repository restore latest --target /restore
```

If the NAS is also gone, you need offline copies of `~/.sops/age-key.txt` and `~/data/`. Compose files survive in git.

#### 2. Run Install

```bash
git clone https://github.com/wajeht/home-ops.git ~/home-ops
cd ~/home-ops && ./scripts/setup.sh install
```

The install script handles Docker, SOPS, networks, and docker-cd deployment.

#### 3. Mount NFS

```bash
./scripts/setup.sh nfs mount
./scripts/setup.sh nfs persist      # survives reboots
```

#### 4. Bootstrap Backrest

```bash
# Restic password lives in apps/backrest/.env.sops — docker-cd decrypts it on deploy
# Data dirs are auto-created on first run if missing
mkdir -p /home/jaw/data/backrest /home/jaw/backup/restic
```

Once Backrest container is up, the schedule resumes automatically.

#### 5. Per-app Restore

Iterate per-app restore procedures above. Order matters for Postgres apps — bring the `*-db` container up first, then run `pg_restore`, then bring the app up.

#### 6. OS Tuning

See [quick-start.md → OS Tuning](quick-start.md#os-tuning) for swappiness and CPU governor.

#### 7. Verify

```bash
./scripts/setup.sh status
# Then in Backrest UI: trigger a manual backup of each plan to confirm hooks fire correctly
```

### After Hardware Migration / Full Redeploy

When swapping hardware or deleting docker-cd state to force a full redeploy:

#### 1. NFS Mounts

NFS mounts drop on reboot/network change. If docker-cd deploys before NFS is mounted, Backrest sees an empty `/home/jaw/backup/restic` and would try to create a new repo:

```bash
./scripts/setup.sh nfs mount
./scripts/setup.sh nfs persist
```

#### 2. Stale Restic Locks

If Backrest was killed mid-backup before the redeploy, its restic locks remain in the repos. After redeploy:

```bash
for app in $(docker exec backrest ls /repos); do
  docker exec backrest restic -r /repos/$app unlock --remove-all
done
```

#### 3. Container Permission Issues

After a fresh deploy, Backrest can crash with `mkdir /data/processlogs: permission denied`. Cause: `cap_drop: ALL` strips capabilities root needs. Already fixed in the compose with `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]`. If you see this on a new install, verify those caps are set.

#### 4. Re-deploying after pushing changes to config.json

A formatter has been observed to strip new entries from `config.json` between push and apply. After any push to `apps/backrest/`, verify on the server:

```bash
jq '(.repos | length), (.plans | length)' ~/home-ops/apps/backrest/config/config.json
# Expect 32 then 32. If either is lower, re-add the missing entries.
```

#### 5. Verify

```bash
docker logs backrest --tail 50          # should be no errors after orchestrator starts
docker exec backrest ls /repos          # should list 32 repos
```

### Testing Recovery

Periodically test by:

1. Spin up a test VM
2. Run the Full Rebuild Procedure
3. Verify each app's data is intact post-restore

A quick on-server drill that doesn't require a VM:

```bash
# Pick a low-stakes app
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore-test
docker exec backrest sqlite3 /tmp/restore-test/source/bang/.bang.bak ".tables"

# Now restore into a SECOND location and diff
docker exec bang sqlite3 /usr/src/app/dist/src/db/sqlite/db.sqlite ".dump" > /tmp/live.sql
docker exec backrest sqlite3 /tmp/restore-test/source/bang/.bang.bak ".dump" > /tmp/backup.sql
diff /tmp/live.sql /tmp/backup.sql | head
```

Diff should be empty or only show data appended since the snapshot was taken.

## Ad-hoc Dumps & Restores with dcdb

Backrest handles scheduled, on-server backups. [dcdb](https://github.com/wajeht/dcdb) is a separate CLI for one-off SQL dumps and restores — a manual point-in-time dump before a risky migration, or cloning prod data into a PR stack. It runs from the laptop and targets the server's containers over SSH; dump files land on the laptop, not the NAS.

Local checkout: `~/Dev/dcdb`. Run via `npx tsx src/index.ts` (or a built `release/` binary).

### Setup

Point the Docker client at the server, then every command targets its containers:

```bash
export DOCKER_HOST=ssh://jaw@192.168.4.161
cd ~/Dev/dcdb
```

### Discover database services

```bash
npx tsx src/index.ts discover              # scan all running compose projects
npx tsx src/index.ts -p <app> discover     # scan one project
```

`-p` is the Compose project (the `apps/<app>` dir name). Add `-s <service>` when a project runs more than one DB service — e.g. `immich` exposes both `immich-db` (postgres) and `immich-redis`.

### Dump

```bash
# single-DB project — service auto-detected
npx tsx src/index.ts -p <app> dump -z ~/Downloads/<app>-<date>.sql.gz

# multi-DB project — name the service
npx tsx src/index.ts -p immich -s immich-db dump -z ~/Downloads/immich-pre-v3.sql.gz
```

- `-z` gzips the output.
- Omit the filename to auto-name `<database>_<timestamp>.sql[.gz]` in the current dir.
- Output path is on the laptop running dcdb.

Verify the dump before trusting it:

```bash
gzip -t ~/Downloads/immich-pre-v3.sql.gz && gunzip -c ~/Downloads/immich-pre-v3.sql.gz | tail -3
```

A valid Postgres dump ends with a `\unrestrict ...` or `-- PostgreSQL database dump complete` trailer.

### Restore

```bash
npx tsx src/index.ts -p <app> -s <service> restore --replace -y ~/Downloads/<app>-<date>.sql.gz
```

- `--replace` clears target data first (Postgres: `DROP SCHEMA public CASCADE; CREATE SCHEMA public`). Without it, the dump layers on top of existing data.
- `-y` skips the confirmation prompt (required for non-interactive runs).
- `.gz` input is auto-decompressed.
- Postgres restore runs with `ON_ERROR_STOP=1` — it fails fast. If it errors midway, rerun the same command.

### Prod → PR clone

```bash
npx tsx src/index.ts -p <app> dump -z /tmp/<app>-prod.sql.gz
npx tsx src/index.ts -p <app>-pr-1 -s <app>-db restore --replace -y /tmp/<app>-prod.sql.gz
```

### Dialect support

| Dialect                        | dump | restore |
| ------------------------------ | ---- | ------- |
| postgres, mariadb/mysql, mongo | yes  | yes     |
| sqlite                         | yes  | yes     |
| redis                          | no   | no      |

Redis dump/restore is unsupported — use Backrest's RDB snapshot hook (see the `cap` plan) for Redis persistence. Full flag reference: [dcdb/docs/cli.md](https://github.com/wajeht/dcdb/blob/main/docs/cli.md).

## Operations

### Force-pull a new Backrest image version

1. In `wajeht/backrest` repo, Renovate PRs the upstream `FROM` tag → auto-merge
2. CI publishes a new `ghcr.io/wajeht/backrest:sha-<hash>` image
3. Manually bump the image line in `apps/backrest/docker-compose.yml`
4. Commit + push → docker-cd pulls and restarts

Renovate **does not** auto-update `ghcr.io/wajeht/*` images in home-ops — this manual step is unavoidable until Renovate's exclusion list is changed.

### Add a new tool to the Backrest image

Edit `Dockerfile` in `wajeht/backrest`:

```dockerfile
FROM ghcr.io/garethgeorge/backrest:vX.Y.Z
RUN apk add --no-cache sqlite postgresql-client jq <new-tool>
```

Push → CI publishes → bump home-ops image digest.

### Inspect a repo from the host

```bash
docker exec backrest restic -r /repos/<app> stats
docker exec backrest restic -r /repos/<app> check
docker exec backrest restic -r /repos/<app> snapshots --json
docker exec backrest restic -r /repos/<app> forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

### Backrest config edits via UI vs git

Backrest's web UI lets you edit config interactively. **Don't do that.** Config is sourced from git via `apps/backrest/config/config.json`. UI changes are lost on next deploy. Always edit the JSON and push.

## Troubleshooting

Known issues and their fixes.

| Symptom                                                                                    | Cause                                                                                     | Fix                                                                                                                               |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `error loading config: ... device or resource busy`                                        | `config.json` mounted as a single file — Backrest's atomic-rename on config updates fails | Mount the **directory** instead: `./config:/config`                                                                               |
| `mkdir /data/processlogs: permission denied`                                               | Backrest container can't write to bind-mounted `/data`                                    | Verify `cap_add` includes `DAC_OVERRIDE`. `DAC_READ_SEARCH` alone is insufficient.                                                |
| `Tini is not running as PID 1` warning on startup                                          | `init: true` set on the compose service — wraps Backrest's tini twice                     | Remove `init: true`. The image already has tini at PID 1.                                                                         |
| Backrest tries to rewrite config.json on every startup                                     | `version` field doesn't match current schema, Backrest tries to migrate it                | Set `"version": 6` explicitly in config.json so Backrest sees the current schema.                                                 |
| Hook fails with `No such container: <app>`                                                 | App container has no `container_name:` set; docker generates `bang-bang-1`-style names    | Add `container_name:` to the app compose with `x-docker-cd.rolling_update: false`, OR use an ephemeral container in the hook      |
| Want both `container_name:` AND rolling updates                                            | Impossible — can't have two containers with the same name during the rolling swap         | Pick one. If rolling-update matters (instant-deploy apps), use ephemeral container approach instead.                              |
| sqlite3 backup fails immediately under concurrent writes                                   | No retry budget configured                                                                | Add `-cmd ".timeout 30000"` before the `.backup` command                                                                          |
| Spaces in DB path break the hook                                                           | Shell word-splitting on unquoted paths                                                    | Wrap each path in **single quotes**. JSON escapes inside double-quoted strings only escape the JSON, not the shell.               |
| Multiple DBs per app                                                                       | One hook can run one shell command                                                        | Chain with `&&` — the whole pre-hook is a single shell line.                                                                      |
| Nested DB path                                                                             | App stores its DB in a subdirectory                                                       | Excludes and sqlite3 paths must match the nested path exactly.                                                                    |
| `unable to create lock in backend: repository is already locked by PID ... on <container>` | Stale lock from killed backup                                                             | `docker exec backrest restic -r /repos/<app> unlock --remove-all` — plain `unlock` only removes non-exclusive locks               |
| Repeated OOM kills during backup                                                           | Memory limit too low — restic's in-memory index spikes well past source size              | Bump `deploy.resources.limits.memory`. Current default is 4G.                                                                     |
| First backup is very slow                                                                  | No dedup baseline; everything has to be written to the new repo                           | Expected. Subsequent backups are seconds.                                                                                         |
| Snapshot succeeds but `.bak`/`.dump` lingers in app dir                                    | Post-hook (CONDITION_SNAPSHOT_END) didn't fire or errored                                 | Check the hook's output in the UI. Common cause: wrong filename in the rm command.                                                |
| ntfy notifications never arrive                                                            | Shoutrrr URL syntax wrong                                                                 | Use `ntfy://ntfy/<topic>?scheme=http&title=foo&priority=Min&tags=skull`. Priority must be capitalized.                            |
| `config.json` entries disappear after pushing                                              | A formatter strips JSON entries it doesn't recognize                                      | After each push, run `jq '(.repos \| length), (.plans \| length)' ~/home-ops/apps/backrest/config/config.json`. Expect 32 and 32. |
| Stateless app got accidentally added to Backrest                                           | Misread of which apps had data                                                            | If `apps/<app>/docker-compose.yml` has no `/home/jaw/data/<app>` volume, skip it. Examples: close-powerlifting, ufc, ip.          |

## Apps Without Backup

Apps that don't need backup, by category:

- **Stateless / config-in-image**: `algo`, `regexr`, `close-powerlifting`, `ufc`, `ip`, `homepage`, `commit`
- **Cache-only or tiny / no persistent state worth backing up**: `renovate`, `ddns-updater`, `byparr`, `dozzle`, `convertx`, `excalidraw`, `git`, `jaw-dev`, `power-badge`
- **Config tracked in git**: `backrest`, `oauth2-proxy`, `docker-cd`. The encrypted oauth2-proxy `.env.sops` includes admin and media email allowlists.
- **Data in object storage**: `linx` — uploads + metadata live in the Garage `linx` bucket, captured by the `garage` plan (no local `~/data/linx`).

If `apps/<app>/docker-compose.yml` has no `/home/jaw/data/<app>` volume, the app is stateless and doesn't need a Backrest plan.
