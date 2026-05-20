# Backrest

Centralized backup using [Backrest](https://github.com/garethgeorge/backrest) (web UI over [restic](https://restic.net)). Replaces per-app `borgmatic` sidecars with a single container that manages all backups.

> **Status:** migration in progress. See [Migration Status](#migration-status). For apps still on borgmatic, see [disaster-recovery.md](disaster-recovery.md).

## Why

Old pattern: one `*-borgmatic` sidecar per app (~44 long-running containers, each with a pinned `postgresql-client` version). New pattern: one Backrest container does everything.

|                   | borgmatic (old)  | Backrest (new)                     |
| ----------------- | ---------------- | ---------------------------------- |
| Idle containers   | 44               | 1                                  |
| Per-app retention | ✅               | ✅ (per plan)                      |
| DB hooks          | borgmatic native | shell hook → `sqlite3` / `pg_dump` |
| Dedup             | ✅ (borg)        | ✅ (restic)                        |
| Restore UI        | ❌ CLI only      | ✅ web UI                          |
| Offsite-ready     | ⚠️ painful       | ✅ trivial (S3/B2 native)          |

## Architecture

```
apps/backrest/
├── docker-compose.yml      # Backrest service
├── config/
│   └── config.json         # repos + plans (committed to git)
├── docker-cd.yml           # rolling_update: false
└── .env.sops               # RESTIC_PASSWORD (shared across all repos)
```

- **Image:** `ghcr.io/wajeht/backrest` — custom build of upstream Backrest with `sqlite`, `postgresql-client`, `jq` baked in. Source: [wajeht/backrest](https://github.com/wajeht/backrest).
- **Web UI:** `https://backrest.jaw.dev` (gated by Google OAuth via Traefik middleware; Backrest's own auth is disabled).
- **Repos:** `/home/jaw/backup/restic/<app>/` — one restic repo per app, all use the same `RESTIC_PASSWORD`.
- **Source data:** `/home/jaw/data/` mounted into Backrest as `/source/` (read-write — pre-backup hooks need to write dump files).
- **Docker socket:** mounted so Backrest hooks can `docker exec` into app containers (e.g., for `pg_dump`).

## Adding an App

For each app, add **one repo + one plan** to `apps/backrest/config/config.json`. Commit + push — docker-cd restarts Backrest with the new config.

### Repo block (same shape for every app)

```json
{
  "id": "<app>",
  "uri": "/repos/<app>",
  "password": "",
  "autoInitialize": true,
  "prunePolicy": {
    "schedule": { "cron": "0 4 * * 0" },
    "maxUnusedPercent": 10
  },
  "checkPolicy": {
    "schedule": { "cron": "0 5 * * 0" },
    "structureOnly": true
  }
}
```

- `password: ""` — falls back to `RESTIC_PASSWORD` env var (shared across all repos)
- `autoInitialize: true` — creates the restic repo on first backup
- Prune Sundays 4am, check Sundays 5am

### Plan: SQLite app (e.g. bang, sonarr, vaultwarden)

```json
{
  "id": "<app>",
  "repo": "<app>",
  "paths": ["/source/<app>/.<app>.bak"],
  "schedule": { "cron": "30 1 * * *", "clock": "CLOCK_LOCAL" },
  "retention": {
    "policyTimeBucketed": { "daily": 7, "weekly": 4, "monthly": 6 }
  },
  "hooks": [
    {
      "conditions": ["CONDITION_SNAPSHOT_START"],
      "onError": "ON_ERROR_CANCEL",
      "actionCommand": {
        "command": "sqlite3 /source/<app>/<path-to-db>.sqlite -cmd \".timeout 30000\" \".backup /source/<app>/.<app>.bak\""
      }
    },
    {
      "conditions": ["CONDITION_SNAPSHOT_END"],
      "actionCommand": {
        "command": "rm -f /source/<app>/.<app>.bak"
      }
    }
  ]
}
```

Pick a unique cron time slot to stagger with existing backups. See [disaster-recovery.md](disaster-recovery.md#per-app-borgmatic) for the current schedule grid.

### Plan: Postgres app (e.g. paperless-ngx, gitea, miniflux)

Use `docker exec` into the app's `*-db` container — that way `pg_dump` always matches the postgres major version (no client-version pinning).

```json
{
  "id": "<app>",
  "repo": "<app>",
  "paths": ["/source/<app>/<files-to-backup>", "/source/<app>/.<app>.dump"],
  "excludes": ["**/<app>/db", "**/<app>/redis", "**/<app>/borgmatic"],
  "schedule": { "cron": "30 0 * * *", "clock": "CLOCK_LOCAL" },
  "retention": {
    "policyTimeBucketed": { "daily": 7, "weekly": 4, "monthly": 6 }
  },
  "hooks": [
    {
      "conditions": ["CONDITION_SNAPSHOT_START"],
      "onError": "ON_ERROR_CANCEL",
      "actionCommand": {
        "command": "docker exec <app>-db pg_dump -U <user> -d <dbname> -F custom > /source/<app>/.<app>.dump"
      }
    },
    {
      "conditions": ["CONDITION_SNAPSHOT_END"],
      "actionCommand": {
        "command": "rm -f /source/<app>/.<app>.dump"
      }
    }
  ]
}
```

The app's `*-db` container needs `container_name: <app>-db` set (already true for all existing postgres apps).

### Plan: File-only app (e.g. adguard, changedetection)

No DB, no hooks — just backup the data dir.

```json
{
  "id": "<app>",
  "repo": "<app>",
  "paths": ["/source/<app>"],
  "excludes": ["**/<app>/borgmatic"],
  "schedule": { "cron": "30 2 * * *", "clock": "CLOCK_LOCAL" },
  "retention": {
    "policyTimeBucketed": { "daily": 7, "weekly": 4, "monthly": 6 }
  }
}
```

## Backup

### Automatic

Every plan runs on its `schedule` cron. Backrest tracks them; no host cron needed.

### Manual trigger

**Via UI:** `https://backrest.jaw.dev` → click plan → **Backup Now**.

**Via CLI:**

```bash
docker exec backrest restic -r /repos/<app> backup /source/<app>
```

(Bypasses Backrest's plan/hooks — use UI to get hooks.)

### Retention / prune / check

Prune (`maxUnusedPercent: 10`) and check (`structureOnly`) run weekly per the repo policy. To trigger manually, use the UI's per-repo actions.

### Notifications

ntfy notifications use Backrest's Shoutrrr action (per [issue #575](https://github.com/garethgeorge/backrest/issues/575)). Two hooks per plan — success and error — matching the original borgmatic priority/tags.

ntfy is on the `traefik` network (alongside `backup`), so Backrest already has reach via its existing `traefik` membership — no extra network needed.

```json
{
  "conditions": ["CONDITION_SNAPSHOT_SUCCESS"],
  "onError": "ON_ERROR_IGNORE",
  "actionShoutrrr": {
    "shoutrrrUrl": "ntfy://ntfy/borgmatic?scheme=http&title=<app>%20backup%20complete&priority=Min&tags=white_check_mark",
    "template": "<app> backup finished"
  }
},
{
  "conditions": ["CONDITION_SNAPSHOT_ERROR"],
  "onError": "ON_ERROR_IGNORE",
  "actionShoutrrr": {
    "shoutrrrUrl": "ntfy://ntfy/borgmatic?scheme=http&title=<app>%20backup%20FAILED&priority=Max&tags=skull",
    "template": "<app> backup failed{{ if .Error }}: {{ .Error }}{{ end }}"
  }
}
```

URL params: `scheme=http` (internal HTTP), `title=` URL-encoded, `priority=Min|Low|Default|High|Max`, `tags=` comma-separated ntfy tag names. The `template` field is the message body (supports [Go template variables](https://github.com/garethgeorge/backrest/blob/main/docs/src/docs/hooks.md#template-system)). Reference: [Shoutrrr ntfy docs](https://containrrr.dev/shoutrrr/v0.8/services/ntfy/).

## Restore

Restoring = pick a snapshot → extract files → put them back. Backrest gives you the files; you handle the app-level swap.

### Via UI (easiest)

1. `https://backrest.jaw.dev` → click plan → **Tree View**
2. Pick a snapshot → click **Restore**
3. Target path: `/tmp/restore` (inside Backrest container). On the host, that's tmpfs — copy out before restart.

### Via CLI

```bash
# list snapshots
docker exec backrest restic -r /repos/<app> snapshots

# restore latest to a temp dir
docker exec backrest restic -r /repos/<app> restore latest --target /tmp/restore

# restore a specific snapshot
docker exec backrest restic -r /repos/<app> restore <id> --target /tmp/restore
```

`RESTIC_PASSWORD` is already in the container env.

### Per-app restore: SQLite

```bash
# 1. Extract
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore

# 2. Stop the app (Backrest's tmpfs survives, but you want bang quiet)
cd ~/home-ops/apps/bang && docker compose stop

# 3. Restore via sqlite3 .restore (canonical inverse of .backup)
docker exec backrest sqlite3 /source/bang/db.sqlite ".restore /tmp/restore/source/bang/.bang.bak"

# 4. Remove stale WAL/SHM (SQLite recreates them on next open)
rm -f /home/jaw/data/bang/db.sqlite-wal /home/jaw/data/bang/db.sqlite-shm

# 5. Start the app
docker compose up -d
```

Alternative for step 3: just `cp /tmp/restore/source/bang/.bang.bak /home/jaw/data/bang/db.sqlite`. Functionally equivalent — `.backup` output is a valid standalone SQLite file. `.restore` is the [SQLite-documented](https://sqlite.org/lang_backup.html) way.

### Per-app restore: Postgres

```bash
# 1. Extract
docker exec backrest restic -r /repos/paperless restore latest --target /tmp/restore

# 2. Restore files (if any)
docker stop paperless-ngx
rsync -a /tmp/restore/source/paperless/ /home/jaw/data/paperless/ \
  --exclude .paperless.dump --exclude db --exclude redis

# 3. Drop + recreate the DB
docker exec paperless-db dropdb -U paperless paperless
docker exec paperless-db createdb -U paperless paperless

# 4. Restore via pg_restore
docker exec -i paperless-db pg_restore -U paperless -d paperless \
  < /home/jaw/data/backrest/dumps/paperless.dump  # adjust path to wherever you copied the .dump

# 5. Start the app
cd ~/home-ops/apps/paperless-ngx && docker compose up -d
```

### Disaster scenarios

| Scenario                                     | Recovery                                                                                                                  |
| -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Backrest container gone, restic repos intact | Spin restic up anywhere with `RESTIC_PASSWORD` → `restic -r /path/to/repo snapshots` works                                |
| Whole server gone, NAS intact                | Restore `~/home-ops` from git, restore `~/.sops` from your password manager, mount NFS, deploy Backrest, restore each app |
| `RESTIC_PASSWORD` lost                       | **No recovery — repos are unreadable.** Keep this password in your password manager.                                      |

### Test it (do this before you need it)

```bash
docker exec backrest restic -r /repos/bang restore latest --target /tmp/restore-test
docker exec backrest sqlite3 /tmp/restore-test/source/bang/.bang.bak ".tables"
```

If `.tables` lists bang's tables, the whole pipeline (backup + restore) works end-to-end.

## Migration Status

Apps marked ✅ are on Backrest. Others still on per-app borgmatic.

- ✅ bang
- ✅ favicon
- ✅ calendar
- ✅ screenshot
- ✅ gains
- ✅ beszel
- ✅ ntfy
- ✅ mm2us
- ✅ uptime-kuma
- ✅ dbgate
- ✅ notify
- ⏳ remaining 33 apps

When all apps are migrated:

1. Delete each app's `*-borgmatic` service + `borgmatic-config.yml` + `borgmatic-crontab.txt`
2. Delete `apps/borgmatic/` (the global file-level backup)
3. Drop the borgmatic sections from [disaster-recovery.md](disaster-recovery.md)

## Operations

### Force-pull a new Backrest image version

```bash
# 1. Update image digest in apps/backrest/docker-compose.yml
# 2. Commit + push — docker-cd pulls and restarts
```

Renovate **does not** auto-update `ghcr.io/wajeht/*` images. To get a new Backrest image:

1. In `wajeht/backrest` repo, Renovate PRs the `FROM` tag → auto-merge
2. CI publishes a new `ghcr.io/wajeht/backrest:sha-<hash>` image
3. Manually bump the image line in `apps/backrest/docker-compose.yml`

### Add a new tool to the Backrest image

Edit `Dockerfile` in `wajeht/backrest`:

```dockerfile
RUN apk add --no-cache sqlite postgresql-client jq <new-tool>
```

Push → CI publishes → bump home-ops.

### Inspect a repo from the host

```bash
docker exec backrest restic -r /repos/<app> stats
docker exec backrest restic -r /repos/<app> check
docker exec backrest restic -r /repos/<app> forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
```

## Troubleshooting

| Symptom                                                                                  | Likely cause                                                          | Fix                                                                                                                          |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `device or resource busy` on `/config/config.json`                                       | Single-file mount of config                                           | Make sure `./config:/config` is a dir mount, not `./config.json:/config/config.json`                                         |
| `mkdir /data/processlogs: permission denied`                                             | Missing `DAC_OVERRIDE` cap                                            | Verify `cap_add` includes `DAC_OVERRIDE`                                                                                     |
| Hook fails with `No such container: <app>`                                               | App container has no `container_name:` set                            | Either add `container_name:` to the app compose (requires `rolling_update: false`) or use an ephemeral container in the hook |
| `Tini is not running as PID 1` warning                                                   | `init: true` set on compose                                           | Remove — Backrest's image already has tini at PID 1                                                                          |
| Snapshot succeeds but `.bak` file lingers in app dir                                     | Post-hook didn't run                                                  | Check `CONDITION_SNAPSHOT_END` hook output in UI                                                                             |
| Config migration tries to rewrite config.json                                            | `version` field stale                                                 | Set `version: 6` in config.json explicitly                                                                                   |
| `unable to create lock in backend: repository is already locked by PID … on <container>` | Stale lock from killed backup (container restart, OOM, manual cancel) | `docker exec backrest restic -r /repos/<app> unlock --remove-all` — plain `unlock` only removes non-exclusive locks          |
| Repeated OOM kills during backup leaving stale locks                                     | Memory limit too low for restic's in-memory indexes                   | Bump `deploy.resources.limits.memory` (default is now 4G). Restic can spike well past the source data size for indexing      |
