# Disaster Recovery

How to back up, restore, and recreate the homelab from scratch.

Backups run through [Backrest](https://github.com/garethgeorge/backrest) (web UI over [restic](https://restic.net)) — a single container managing per-app restic repos, with web-UI restore and ntfy notifications.

## What's Backed Up Where

| Data                  | Location                | Backup Strategy                                          |
| --------------------- | ----------------------- | -------------------------------------------------------- |
| App configs/databases | `~/data/`               | Per-app Backrest plan → NAS (`~/backup/restic/<app>/`)   |
| SOPS age key          | `~/.sops/age-key.txt`   | Backrest `global` plan → NAS (`~/backup/restic/global/`) |
| All `~/data/` raw     | `~/data/`               | Backrest `global` plan (belt-and-suspenders, file-level) |
| Docker auth           | `~/.docker/config.json` | Recreatable via `docker login`                           |
| Secrets               | `.env.sops` files       | Encrypted in git                                         |
| Media files           | `~/plex/` (NFS)         | NAS handles redundancy                                   |
| Immich photos         | `~/immich/` (NFS)       | NAS handles redundancy                                   |
| Compose files         | Git repo                | Already backed up                                        |

## Critical Files

```bash
# These MUST be backed up — can't recreate without them
~/.sops/age-key.txt           # Decrypts all .env.sops secrets
~/data/                       # All app configs and databases
RESTIC_PASSWORD               # In apps/backrest/.env.sops — without it, NO restic repo is readable
```

> **`RESTIC_PASSWORD` is the master key for all backups.** Without it, every restic repo is permanently unrecoverable. Keep it in your password manager. The age key is its only counterpart on the secrets side — same rule applies.

## Architecture

```
apps/backrest/
├── docker-compose.yml      # Backrest service
├── config/
│   └── config.json         # repos + plans (committed to git)
├── docker-cd.yml           # rolling_update: false
└── .env.sops               # RESTIC_PASSWORD (shared across all repos)
```

- **Image:** `ghcr.io/wajeht/backrest` — custom build of upstream Backrest with `sqlite`, `postgresql-client`, `jq` baked in. Source: [wajeht/backrest](https://github.com/wajeht/backrest). Renovate **does not** auto-update `ghcr.io/wajeht/*` images — manually bump the digest when a new version is published.
- **Web UI:** `https://backrest.jaw.dev` (gated by Google OAuth via Traefik middleware; Backrest's own auth is disabled).
- **Repos:** `/home/jaw/backup/restic/<app>/` — one restic repo per app + one `global`. All use the same shared `RESTIC_PASSWORD`.
- **Source data:** `/home/jaw/data/` mounted into Backrest as `/source/` (read-write — pre-backup hooks need to write dump files into per-app data dirs).
- **SOPS age key:** `/home/jaw/.sops/` mounted as `/sops/` (read-only) — only the global plan reads this.
- **Docker socket:** mounted (read-write) so hooks can `docker exec` into app containers for `pg_dump`.
- **Resource limits:** 2 CPU / 4 GB memory. Restic's in-memory index can spike well past source data size on large backups — 1 GB caused repeated OOMs.

## Backup Schedule

Per-app schedules are staggered to prevent resource contention. `global` runs last after all per-app backups complete.

| App            | Schedule | Type                 | Notes                                                          |
| -------------- | -------- | -------------------- | -------------------------------------------------------------- |
| plausible      | 12:05 AM | Postgres + files     | ClickHouse `events/` backed up raw                             |
| hello-world    | 12:25 AM | Postgres (DB only)   |                                                                |
| immich         | 12:35 AM | Postgres (DB only)   | Photos at `~/immich` (NFS) NOT backed up — NAS-redundant       |
| uptime-kuma    | 12:40 AM | SQLite + files       | DB file is `kuma.db`                                           |
| gatus          | 12:42 AM | SQLite + files       | DB file is `gatus.db`                                          |
| sonarr         | 12:50 AM | SQLite + files       | Excludes logs.db, asp, Sentry, \*.pid                          |
| radarr         | 12:55 AM | SQLite + files       | Excludes MediaCover, Backups (in addition to sonarr's)         |
| prowlarr       | 1:00 AM  | SQLite + files       |                                                                |
| tautulli       | 1:05 AM  | SQLite + files       | Excludes cache, logs, \*.lock                                  |
| audiobookshelf | 1:10 AM  | SQLite + files       | DB at `config/absdatabase.sqlite`                              |
| ntfy           | 1:20 AM  | SQLite (×2) + files  | Two DBs: `user.db` + `cache.db` (chained in hook)              |
| bang           | 1:30 AM  | SQLite (DB only)     | Ephemeral keinos/sqlite3 — bang has no `container_name`        |
| favicon        | 1:35 AM  | SQLite + files       |                                                                |
| mm2us          | 1:40 AM  | SQLite (DB only)     |                                                                |
| notify         | 1:45 AM  | SQLite (DB only)     |                                                                |
| calendar       | 1:50 AM  | SQLite (DB only)     |                                                                |
| screenshot     | 1:55 AM  | SQLite + files       |                                                                |
| gains          | 2:00 AM  | SQLite (DB only)     |                                                                |
| homeassistant  | 2:05 AM  | SQLite + files       | DB file is `home-assistant_v2.db`                              |
| zigbee2mqtt    | 2:10 AM  | Files only           |                                                                |
| dbgate         | 2:15 AM  | Files only           | `/mnt/*` mounts to other apps' data NOT backed up here         |
| listenarr      | 2:25 AM  | SQLite + files       | DB at `database/listenarr.db`                                  |
| garage         | 2:30 AM  | Files only           | meta + data dirs (S3 bucket contents — can be large)           |
| beszel         | 2:35 AM  | SQLite + files       | DB file is `data.db`                                           |
| traefik        | 2:40 AM  | Files only           | Includes `acme.json` certs                                     |
| plex           | 2:45 AM  | SQLite (×2) + files  | Two DBs deeply nested under `Library/Application Support/...`  |
| seerr          | 2:50 AM  | SQLite + files       | DB at `db/db.sqlite3`                                          |
| bazarr         | 2:55 AM  | SQLite + files       | DB at `db/bazarr.db`                                           |
| sabnzbd        | 3:00 AM  | SQLite + files       | DB at `admin/history1.db`. Excludes Downloads (huge transient) |
| vpn-qbit       | 3:05 AM  | Files only           | Two source paths: qbittorrent + gluetun                        |
| nut            | 3:10 AM  | Files only           | Peanut config                                                  |
| vaultwarden    | 3:15 AM  | SQLite + files       | DB file is `db.sqlite3`                                        |
| gitea          | 3:20 AM  | SQLite + files       | DB at `gitea/gitea.db`. Includes all git repos                 |
| **global**     | 3:45 AM  | All ~/data + ~/.sops | File-level only. Excludes `*.bak`, `*.dump`, backrest state    |

Retention is **7 daily / 4 weekly / 6 monthly** for every plan. Prune runs Sunday 4 AM, integrity check Sunday 5 AM (structure-only).

## Adding an App

For each app, add **one repo + one plan** to `apps/backrest/config/config.json`. Commit + push — docker-cd restarts Backrest with the new config.

> **Critical:** After pushing, verify the entries are still in `config.json` on the server. A formatter has been observed to strip new JSON entries on some pushes — confirm before assuming the change took effect.

### Repo block (same shape for every app)

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

### Plan: SQLite, DB-only (bang, calendar, gains, mm2us, notify)

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

### Plan: SQLite + files (most apps)

Same as DB-only, but `paths` is the whole data dir and excludes filter out raw DB files:

```json
{
  "paths": ["/source/<app>"],
  "excludes": ["**/<app>/<db-file>.db", "**/<app>/<db-file>.db-wal", "**/<app>/<db-file>.db-shm"]
}
```

### Plan: Postgres (plausible, immich, etc.)

Use `docker exec` into the app's `*-db` container — `pg_dump` always matches the postgres major version. Use `docker cp` to pull the dump out (don't redirect stdout cross-container):

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

The app's `*-db` container needs `container_name: <app>-db` set (already true for all existing Postgres apps).

### Plan: Files-only (dbgate, garage, nut, traefik, vpn-qbit, zigbee2mqtt)

```json
{
  "paths": ["/source/<app>"],
  "hooks": [
    /* only ntfy success/error hooks, no DB hooks */
  ]
}
```

### Plan: Multiple SQLite DBs (ntfy, plex)

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

### Plan: App without `container_name` (bang)

If the app uses `rolling_update: true` (apps deployed via instant-deploy, e.g. bang), adding `container_name` breaks rolling updates because docker can't have two containers with the same name during the swap. Use an ephemeral container instead:

```json
"command": "docker run --rm -v /home/jaw/data/bang:/data keinos/sqlite3:3.51.3@sha256:520cfebb116119cc642b72d72c3ff948cc120a891dc4d83824c664f1ca65a354 sqlite3 /data/db.sqlite \".backup /data/.bang.bak\""
```

Trade-offs: rolling updates preserved; cost is image pull on first run + extra exec overhead. Use only when needed.

### Notifications

ntfy via Backrest's Shoutrrr action (per [issue #575](https://github.com/garethgeorge/backrest/issues/575)). Two hooks per plan — success and error:

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

URL params: `scheme=http`, `title=<URL-encoded>`, `priority=Min|Low|Default|High|Max` (capitalized), `tags=<comma-separated>`. ntfy is reachable on the `traefik` network — no extra network mount needed.

## Backup Commands

### Manual trigger

**Via UI:** `https://backrest.jaw.dev` → click plan → **Backup Now** (runs the full plan with hooks).

**Via CLI** (bypasses hooks — only for sanity-checking):

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

If a backup is killed mid-run (container restart, OOM, manual cancel), restic leaves a lock file in the repo. Subsequent operations fail with `unable to create lock in backend: repository is already locked by PID ...`. Fix:

```bash
docker exec backrest restic -r /repos/<app> unlock --remove-all
```

Plain `unlock` only removes non-exclusive locks. `--remove-all` clears exclusive locks too.

## Restore

Restoring = pick a snapshot → extract files → put them back. Backrest gives you the files; you handle the app-level swap.

### Via UI (easiest)

1. `https://backrest.jaw.dev` → click plan → **Tree View**
2. Pick a snapshot → click **Restore**
3. Target path: `/tmp/restore` (inside Backrest container; on host this is tmpfs — copy out before restart).

### Via CLI

```bash
docker exec backrest restic -r /repos/<app> snapshots                      # list snapshots
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore
docker exec backrest restic -r /repos/<app> restore <id> --target /tmp/restore  # specific snapshot
```

### Restore: SQLite DB-only (bang, calendar, gains, mm2us, notify)

```bash
# 1. Extract
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore

# 2. Stop the app
cd ~/home-ops/apps/bang && docker compose stop

# 3. Restore via sqlite3 .restore (canonical inverse of .backup)
docker exec backrest sqlite3 /source/bang/db.sqlite ".restore /tmp/restore/source/bang/.bang.bak"

# 4. Remove stale WAL/SHM (SQLite recreates them on next open)
rm -f /home/jaw/data/bang/db.sqlite-wal /home/jaw/data/bang/db.sqlite-shm

# 5. Start the app
docker compose up -d
```

Alternative for step 3: `cp /tmp/restore/source/bang/.bang.bak /home/jaw/data/bang/db.sqlite` — functionally equivalent because `.backup` output is a valid standalone SQLite file. `.restore` is the [SQLite-documented](https://sqlite.org/lang_backup.html) canonical way.

### Restore: SQLite + files (most apps)

```bash
# 1. Extract everything
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore

# 2. Stop the app
cd ~/home-ops/apps/<app> && docker compose stop

# 3. Restore files (exclude the .bak — that goes to the DB)
rsync -a --delete /tmp/restore/source/<app>/ /home/jaw/data/<app>/ --exclude '.<app>.bak'

# 4. Restore DB via sqlite3 .restore
docker exec backrest sqlite3 /home/jaw/data/<app>/<db-file>.db ".restore /tmp/restore/source/<app>/.<app>.bak"

# 5. Remove stale WAL/SHM
rm -f /home/jaw/data/<app>/<db-file>.db-wal /home/jaw/data/<app>/<db-file>.db-shm

# 6. Start
docker compose up -d
```

### Restore: Postgres DB-only (hello-world, immich)

```bash
# 1. Extract
docker exec backrest restic -r /repos/hello-world restore latest --target /tmp/restore

# 2. Bring DB container up (rest of app can stay down)
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

### Restore: Postgres + files (plausible)

```bash
# 1. Extract
docker exec backrest restic -r /repos/plausible restore latest --target /tmp/restore

# 2. Stop the app
cd ~/home-ops/apps/plausible && docker compose stop plausible

# 3. Restore files (exclude .dump and the raw db dir)
rsync -a --delete /tmp/restore/source/plausible/ /home/jaw/data/plausible/ \
  --exclude '.plausible.dump' --exclude 'db'

# 4. Drop + recreate the DB
docker exec plausible-db dropdb -U plausible plausible
docker exec plausible-db createdb -U plausible plausible

# 5. pg_restore
docker cp /tmp/restore/source/plausible/.plausible.dump plausible-db:/tmp/restore.dump
docker exec plausible-db pg_restore -U plausible -d plausible /tmp/restore.dump
docker exec plausible-db rm /tmp/restore.dump

# 6. Start
docker compose up -d
```

### Restore: Files only (dbgate, garage, nut, traefik, vpn-qbit, zigbee2mqtt)

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

### Restore: Multiple DBs in one app (ntfy, plex)

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

Without `~/.sops/age-key.txt`, every `.env.sops` is unreadable — recovery from this state requires either the age key OR plaintext copies of every secret. **Back up the age key to multiple locations** (password manager, second offline copy).

### Test restore drill (do this monthly)

```bash
# Pick a small repo
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore-test
docker exec backrest sqlite3 /tmp/restore-test/source/bang/.bang.bak ".tables"
```

If `.tables` lists bang's tables, the full pipeline (backup + restore) works end-to-end. The cheapest way to discover backup rot before you need it.

## Disaster Recovery

### Scenarios

| Scenario                                         | Recovery                                                                                                                                                          |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| One app's data lost, NAS intact                  | Restore that app from `/repos/<app>` using the per-app restore procedure above                                                                                    |
| One app's DB corrupted but files OK              | Restore just the `.bak`/`.dump` via `--include`, then `sqlite3 .restore` or `pg_restore`                                                                          |
| Backrest container gone, restic repos intact     | Spin restic up anywhere with the password: `docker run --rm -e RESTIC_PASSWORD=… -v /mnt/nas/backup/restic:/repos restic/restic:latest -r /repos/<app> snapshots` |
| Backrest config.json corrupted                   | Restore from git (`apps/backrest/config/config.json`) — the source of truth                                                                                       |
| Whole local server gone, NAS intact              | Restore `~/home-ops` from git → restore `~/.sops/age-key.txt` from your password manager → mount NFS → deploy Backrest → restore each app                         |
| `RESTIC_PASSWORD` lost                           | **No recovery — every restic repo is permanently unreadable.** Keep this password in your password manager.                                                       |
| SOPS age key lost AND not in Backrest repo       | Every `.env.sops` is unreadable. Restoring `.env` plaintext copies (if any exist) is the only path. **Back up the age key to multiple offline locations.**        |
| Restic repo + age key + RESTIC_PASSWORD all lost | Full data loss for that app. Compose files in git still survive — apps can be redeployed empty, configs lost.                                                     |

### Full Rebuild Procedure

#### 1. Restore Critical Files

If the NAS is intact:

```bash
# Mount NFS backup share
./scripts/home-ops.sh nfs mount backup

# Restore the global snapshot (gets ~/data and ~/.sops in one shot)
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
cd ~/home-ops && ./scripts/home-ops.sh install
```

The install script handles Docker, SOPS, networks, and docker-cd deployment.

#### 3. Mount NFS and SATA

```bash
./scripts/home-ops.sh nfs mount
./scripts/home-ops.sh nfs persist      # survives reboots
./scripts/home-ops.sh sata persist     # survives reboots
```

#### 4. Bootstrap Backrest

```bash
# Restic password lives in apps/backrest/.env.sops — docker-cd decrypts it on deploy
# Data dirs are auto-created on first run if missing
mkdir -p /home/jaw/data/backrest /home/jaw/backup/restic
```

Once Backrest container is up, the schedule resumes automatically.

#### 5. Per-app Restore (only if `~/data/<app>/` was lost or is stale)

Iterate per-app restore procedures above. Order matters for Postgres apps — bring the `*-db` container up first, then run `pg_restore`, then bring the app up.

#### 6. OS Tuning

See [quick-start.md → OS Tuning](quick-start.md#os-tuning) for swappiness and CPU governor.

#### 7. Verify

```bash
./scripts/home-ops.sh status
# Then in Backrest UI: trigger a manual backup of each plan to confirm hooks fire correctly
```

### After Hardware Migration / Full Redeploy

When swapping hardware or deleting docker-cd state to force a full redeploy:

#### 1. NFS Mounts (fix FIRST)

NFS mounts drop on reboot/network change. If docker-cd deploys before NFS is mounted, Backrest sees an empty `/home/jaw/backup/restic` and would try to create a new (empty) repo:

```bash
make nfs-mount
make nfs-persist
```

#### 2. SATA Mount

```bash
make sata-mount
make sata-persist
```

#### 3. Stale Restic Locks

If Backrest was killed mid-backup before the redeploy, its restic locks remain in the repos. After redeploy:

```bash
for app in $(docker exec backrest ls /repos); do
  docker exec backrest restic -r /repos/$app unlock --remove-all
done
```

#### 4. Container Permission Issues

After a fresh deploy, Backrest can crash with `mkdir /data/processlogs: permission denied`. Cause: `cap_drop: ALL` strips capabilities root needs. Already fixed in the compose with `cap_add: [CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID]`. If you see this on a new install, verify those caps are set.

#### 5. Re-deploying after pushing changes to config.json

A formatter has been observed to strip new entries from `config.json` between push and apply. After any push to `apps/backrest/`, verify on the server:

```bash
grep -c '"id":' ~/home-ops/apps/backrest/config/config.json
# Expect 84 (42 repos × 42 plans). If lower, re-add the missing entries.
```

#### 6. Verify

```bash
docker logs backrest --tail 50          # should be no errors after orchestrator starts
docker exec backrest ls /repos          # should list 42 repos
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

Diff should be empty (if no writes since the backup) or only show data appended since the snapshot was taken.

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

| Symptom                                                                                    | Cause                                                                                     | Fix                                                                                                                       |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| `error loading config: ... device or resource busy`                                        | `config.json` mounted as a single file — Backrest's atomic-rename on config updates fails | Mount the **directory** instead: `./config:/config` (not `./config.json:/config/config.json`)                             |
| `mkdir /data/processlogs: permission denied`                                               | Backrest container can't write to bind-mounted `/data`                                    | Verify `cap_add` includes `DAC_OVERRIDE`. `DAC_READ_SEARCH` alone is insufficient.                                        |
| `Tini is not running as PID 1` warning on startup                                          | `init: true` set on the compose service — wraps Backrest's tini twice                     | Remove `init: true`. The image already has tini at PID 1.                                                                 |
| Backrest tries to rewrite config.json on every startup                                     | `version` field doesn't match current schema, Backrest tries to migrate it                | Set `"version": 6` explicitly in config.json so Backrest sees the current schema.                                         |
| Hook fails with `No such container: <app>`                                                 | App container has no `container_name:` set; docker generates `bang-bang-1`-style names    | Add `container_name:` to the app compose (requires `rolling_update: false`), OR use an ephemeral container in the hook    |
| Want both `container_name:` AND rolling updates                                            | Impossible — can't have two containers with the same name during the rolling swap         | Pick one. If rolling-update matters (instant-deploy apps), use ephemeral container approach instead.                      |
| sqlite3 backup fails immediately under concurrent writes                                   | No retry budget configured                                                                | Add `-cmd ".timeout 30000"` before the `.backup` command (30-second retry window).                                        |
| Spaces in DB path break the hook (e.g. plex)                                               | Shell word-splitting on unquoted paths                                                    | Wrap each path in **single quotes**. JSON escapes inside double-quoted strings only escape the JSON, not the shell.       |
| Multiple DBs per app (ntfy, plex)                                                          | One hook can run one shell command                                                        | Chain with `&&` — the whole pre-hook is a single shell line.                                                              |
| Nested DB path (seerr → `db/db.sqlite3`, gitea → `gitea/gitea.db`)                         | App stores its DB in a subdirectory                                                       | Excludes and sqlite3 paths must match the nested path exactly.                                                            |
| `unable to create lock in backend: repository is already locked by PID ... on <container>` | Stale lock from killed backup (container restart, OOM, cancel)                            | `docker exec backrest restic -r /repos/<app> unlock --remove-all` — plain `unlock` only removes non-exclusive locks       |
| Repeated OOM kills during backup                                                           | Memory limit too low — restic's in-memory index spikes well past source size              | Bump `deploy.resources.limits.memory`. Current default is 4G.                                                             |
| First backup is very slow (minutes for ~200MB)                                             | No dedup baseline; everything has to be written to the new repo                           | Expected. Subsequent backups are seconds (only delta blocks).                                                             |
| Snapshot succeeds but `.bak`/`.dump` lingers in app dir                                    | Post-hook (CONDITION_SNAPSHOT_END) didn't fire or errored                                 | Check the hook's output in the UI. Common cause: wrong filename in the rm command.                                        |
| `Cannot load garage config!` repeating in garage-webui logs                                | Image expects `/etc/garage.toml`, has env-var fallbacks                                   | Non-fatal — webui works via env vars. Ignore.                                                                             |
| Bad gateway 502 on first click of garage image link, works on retry                        | garage-webui's pool connection to garage:3900 went stale                                  | Add Traefik retry middleware to the route. Backrest unrelated.                                                            |
| ntfy notifications never arrive                                                            | Shoutrrr URL syntax wrong                                                                 | Use `ntfy://ntfy/<topic>?scheme=http&title=foo&priority=Min&tags=skull`. Priority must be capitalized (`Min`, not `min`). |
| First Shoutrrr push broke Backrest container                                               | Actually didn't — first deploy succeeded; later deploy hung during a backup               | Make sure no backup is running when redeploying. Backrest can't recreate while restic process holds files.                |
| `config.json` entries disappear after pushing                                              | A formatter (locally or in CI) strips JSON entries it doesn't recognize                   | After each push, `grep -c '"id":' ~/home-ops/apps/backrest/config/config.json` on the server. Expected count: 84.         |
| Stateless app got accidentally added to Backrest                                           | Misread of which apps had data                                                            | If `apps/<app>/docker-compose.yml` has no `/home/jaw/data/<app>` volume, skip it. Examples: close-powerlifting, ufc, ip.  |

## Apps Without Backup (Intentional)

Apps that don't need backup, by category:

- **Stateless / config-in-image**: `close-powerlifting`, `ufc`, `ip`, `homepage`, `commit`
- **Cache-only or tiny / no persistent state worth backing up**: `hindsight`, `recyclarr`, `renovate`, `ddns-updater`, `searxng`, `walker`, `zepp`, `code-server`, `readmeabook`, `stirling-pdf`, `byparr`, `dozzle`, `convertx`, `excalidraw`, `git`, `it-tools`, `jaw-dev`, `scrypted`, `speedtest`, `power-badge`, `adguard`
- **Infra (config tracked in git)**: `backrest`, `google-auth`, `google-auth-user`

If `apps/<app>/docker-compose.yml` has no `/home/jaw/data/<app>` volume, the app is stateless and doesn't need a Backrest plan.
