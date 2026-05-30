# cap

Self-hosted, privacy-first CAPTCHA alternative to reCAPTCHA, powered by proof-of-work + instrumentation challenges ([tiagozip/cap](https://github.com/tiagozip/cap)).

Dashboard: `https://cap.jaw.dev` (login with `ADMIN_KEY`)
Docs: <https://capjs.js.org/guide/standalone/>

## Public by design

Cap is **not** behind `oauth2-*` — the widget assets and challenge API must be reachable by browsers on every site you protect. The router uses `rate-limit-global@file` only. The admin dashboard is gated by `ADMIN_KEY` (set in `.env.sops`, min 12 chars; we generate 64 hex). Rotate with:

```bash
export SOPS_AGE_KEY_FILE=./.sops/age-key.txt
sops --input-type dotenv --output-type dotenv apps/cap/.env.sops
```

## State lives in Redis

All site keys, sessions, settings, and challenge state are stored in `cap-redis` (`REDIS_URL`) — there is no SQLite/Postgres. Redis runs in RDB mode (`--save 60 1`, matching upstream), persisted at `~/data/cap/redis`. The Backrest plan `cap` runs `redis-cli SAVE` then snapshots `dump.rdb` (see [disaster-recovery.md](../../docs/disaster-recovery.md)). If Redis is lost, recreate the site key in the dashboard and update the embedding sites — nothing else is destroyed.

`ENABLE_ASSETS_SERVER=true` serves the widget JS/WASM from `cap.jaw.dev/assets/...`, so embedding sites don't depend on a third-party CDN. `CORS_ORIGIN` defaults to `*`; restrict it (env var) if you want only your own domains to consume challenges.

## Caps

- `cap` runs as the non-root `bun` user on `oven/bun:slim` and binds port 3000 — no `cap_add` needed. Root FS is `read_only`; `/usr/src/app/data` (optional GeoIP cache) and `/tmp` are tmpfs.
- `cap-redis` needs `CHOWN, DAC_OVERRIDE, FOWNER, SETGID, SETUID` — the official entrypoint chowns the bind-mounted `/data` on first start, then drops to the `redis` user via gosu.
