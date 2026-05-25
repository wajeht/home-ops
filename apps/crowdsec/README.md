# CrowdSec

CrowdSec bans malicious IPs at Traefik before they reach apps. The agent parses Traefik's access log, runs detection scenarios, and pulls a community blocklist of known-bad IPs. A Yaegi plugin inside Traefik consults a local cache of decisions on every request and returns 403 for banned IPs; the cache refreshes from the agent's LAPI every 60s (stream mode).

A web UI sidecar ([`crowdsec-web-ui`](https://github.com/TheDuffman85/crowdsec-web-ui)) runs in the same compose stack and exposes a dashboard at `crowdsec.jaw.dev` (behind google-auth) showing alerts, decisions, geo-IP for attackers, and AS info.

## How It Works

```
Cloudflare edge
       ↓  (cloudflare-only middleware: only CF IPs reach origin)
Traefik
   ├── crowdsec@file middleware    → checks local decision cache
   │                                  403 if IP is banned, pass-through if not
   │                                  cache refreshed from LAPI every 60s (stream mode)
   └── writes JSON access log → traefik-logs volume
                                       ↓
CrowdSec agent (apps/crowdsec)
   - tails /var/log/traefik/access.log
   - collections: crowdsecurity/traefik, crowdsecurity/http-cve
   - pulls community blocklist (thousands of known-bad IPs)
   - LAPI on :8080, internal traefik network only
```

The plugin is loaded via `--experimental.plugins.bouncer.*` in `apps/traefik/docker-compose.yml`. It's downloaded from GitHub on Traefik start and cached inside the container. The middleware itself is defined in `apps/traefik/dynamic.yml` (file provider), so it exists the moment Traefik reads its dynamic config — no race with the docker provider.

Order of the default middleware chain on `websecure`:

```
cloudflare-only@file → crowdsec@file → gzip@file → security-headers@file
```

`cloudflare-only` runs first (cheap CIDR check), so CrowdSec only sees real client traffic from CF.

## Design Choices

A few non-obvious decisions, with reasoning so they're easy to revisit later.

**Middleware in `dynamic.yml` (`@file`), not Docker labels (`@docker`).** Traefik's file provider loads `dynamic.yml` synchronously at startup. The docker provider enumerates containers asynchronously a moment later. If the bouncer middleware were defined via docker labels, the `catchall` router (defined in `dynamic.yml`) would fail to resolve `crowdsec@docker` for the brief window before the docker provider catches up, logging an error on every Traefik restart. Defining the middleware in `dynamic.yml` makes it available the instant Traefik reads the file — no race.

**Stream mode, not live mode.** Live mode hits LAPI on every request; stream mode pulls all decisions in the background every 60s and serves blocks from a local cache. Upstream recommends stream mode for performance — request latency is unaffected by LAPI roundtrip, and LAPI sees one sync per minute instead of one query per request.

**Key via `crowdsecLapiKeyFile` + Docker Compose secret, not env interpolation in YAML.** The plugin's official `crowdsecLapiKeyFile` option lets it read the key from a file path. We use Compose's `secrets.environment: CROWDSEC_BOUNCER_KEY` to source the value from `.env` (decrypted from `.env.sops` by docker-cd) and mount it at `/run/secrets/crowdsec_lapi_key` (tmpfs, never written to host disk). The result: the key never appears in any committed YAML and never lands on the host filesystem.

**`rolling_update: false` in `docker-cd.yml`.** CrowdSec holds a SQLite DB and long-lived bouncer registrations. Two parallel instances during a rolling swap would race on the DB and confuse the bouncer-key registration. Better to take a few seconds of fail-open during redeploy than risk DB corruption.

**`http-probing` and `http-crawl-non_statics` disabled.** These two scenarios from `crowdsecurity/traefik` are volume-based (fire on many 404s or many non-static requests from one IP in a window) and produce false positives on normal SPA browsing — the SPA hits a missing asset, the agent sees a probing pattern, the IP gets banned. Same false positive shows up in upstream reports against Nextcloud, Immich, and other selfhosted apps. The signature-based scenarios in the collection (sqli/xss/path-traversal/sensitive-files/bad-UA/backdoors/brute-force, plus the entire `crowdsecurity/http-cve` collection) are kept — they detect _what's in the request_, not how many requests. Mainstream homelab practice; the CrowdSec docs themselves use `http-probing` as the canonical `cscli scenarios remove` example.

## Real Client IP

Bans key off `CF-Connecting-IP`, not the immediate source IP (which is always Cloudflare). The middleware's `forwardedHeadersCustomName` is set to `CF-Connecting-IP` and `forwardedHeadersTrustedIPs` lists the same CF ranges already trusted elsewhere in the stack.

## API Key Handling

The bouncer API key is stored in `apps/traefik/.env.sops` as `CROWDSEC_BOUNCER_KEY` (encrypted) and in `apps/crowdsec/.env.sops` as `BOUNCER_KEY_TRAEFIK` — same value, two stacks. The agent reads it via the `BOUNCER_KEY_*` env-var convention to auto-register a bouncer named `traefik` at boot. Traefik consumes it via a Docker Compose secret (`secrets.environment: CROWDSEC_BOUNCER_KEY`) which is mounted at `/run/secrets/crowdsec_lapi_key` (tmpfs) and read by the middleware via `crowdsecLapiKeyFile`. The key never appears in any committed YAML file.

Internal LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) are in `clientTrustedIPs` — they can never be banned.

## Pre-Deploy Setup

On a new host, before the first deploy, create the data dirs:

```bash
mkdir -p /home/jaw/data/crowdsec/{db,config}
mkdir -p /home/jaw/data/crowdsec-web-ui
```

The bouncer API key is already populated in both `.env.sops` files — no manual step. If you ever need to rotate it, regenerate one value and update both files (`apps/traefik/.env.sops` and `apps/crowdsec/.env.sops`) before redeploying.

### Bootstrapping the Web UI watcher

The UI authenticates to LAPI as a watcher (machine), separate from the bouncer key. On a fresh setup the machine doesn't exist yet — register it once:

```bash
docker exec crowdsec cscli machines add crowdsec-web-ui --auto -f -
```

Note: `-f -` prints to stdout (default `--auto` would try to write to `/etc/crowdsec/local_api_credentials.yaml`, which is already in use by the agent itself).

Capture the printed `login` and `password`, then add them to `apps/crowdsec/.env.sops`:

```
CROWDSEC_WEB_UI_USER=crowdsec-web-ui
CROWDSEC_WEB_UI_PASSWORD=<paste here>
```

Re-encrypt with `sops -e --input-type dotenv --output-type dotenv .env > .env.sops && rm .env`. The UI service reads both vars and authenticates on first start.

To rotate the password: `docker exec crowdsec cscli machines delete crowdsec-web-ui` then repeat the steps above.

## SQLite WAL Mode

`USE_WAL: "true"` is set in the agent's compose. Without it the agent logs:

```
sqlite is not using WAL mode, LAPI might become unresponsive when inserting the community blocklist
```

WAL (Write-Ahead Logging) lets the bouncer plugin read decisions concurrently with the agent inserting the community blocklist. Without WAL, the blocklist update (≥2700 row inserts at boot, plus periodic resyncs) holds a write lock long enough to make LAPI queries time out.

CrowdSec creates `crowdsec.db-wal` and `crowdsec.db-shm` sidecar files alongside `crowdsec.db`. The Backrest plan excludes both — only the main `crowdsec.db` (post-sqlite3 `.backup`) goes into snapshots.

## Common Operations

All commands run from inside the `crowdsec` container.

### List active bans

```bash
docker exec crowdsec cscli decisions list
```

### Ban an IP manually

```bash
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 4h --reason "manual"
```

### Unban an IP

```bash
docker exec crowdsec cscli decisions delete --ip 1.2.3.4
```

### Permanent whitelist

Edit `/home/jaw/data/crowdsec/config/parsers/s02-enrich/whitelists.yaml`:

```yaml
name: crowdsecurity/whitelists
description: "Trusted IPs"
whitelist:
  reason: "trusted"
  ip:
    - 203.0.113.1
  cidr:
    - 203.0.113.0/24
```

Then restart the agent: `docker restart crowdsec`.

### Inspect metrics

```bash
docker exec crowdsec cscli metrics
```

Shows lines parsed per source, bucket overflow counts, and bouncer query rate.

### Verify bouncer is registered

```bash
docker exec crowdsec cscli bouncers list
```

Should show `traefik` with `valid` status.

### Tail the agent log

```bash
docker logs -f crowdsec
```

## Validating It Works

Manual ban end-to-end test:

```bash
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --duration 5m
docker exec traefik wget -qO- -S --header="CF-Connecting-IP: 1.2.3.4" \
  http://hello-world/
# → expect 403
docker exec traefik wget -qO- -S --header="CF-Connecting-IP: 8.8.8.8" \
  http://hello-world/
# → expect 200
```

Community blocklist count (should be in the thousands within ~10 min of agent boot):

```bash
docker exec crowdsec cscli decisions list -o raw | wc -l
```

## Failure Modes

| Symptom                                                                      | Cause                                                                | Fix                                                                                                                                                                            |
| ---------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Traefik refuses to start, log mentions plugin                                | Yaegi can't fetch plugin (no internet, GitHub down)                  | Revert the `--experimental.plugins.*` lines in `apps/traefik/docker-compose.yml`, redeploy.                                                                                    |
| LAPI unreachable, requests still pass                                        | Plugin default `defaultDecision=allow`                               | Working as designed — fail-open avoids self-lockout when CrowdSec crashes.                                                                                                     |
| Legit user banned (false positive)                                           | A behavioral scenario over-fired                                     | `cscli decisions delete --ip <ip>` and add to the whitelist file above.                                                                                                        |
| Agent banning Cloudflare IPs                                                 | Real-client header not extracted                                     | In `apps/traefik/dynamic.yml`, confirm `forwardedHeadersCustomName: CF-Connecting-IP` and CF ranges are in `forwardedHeadersTrustedIPs`.                                       |
| Bouncer shows `invalid` in `cscli bouncers list`                             | Key mismatch                                                         | Confirm `CROWDSEC_BOUNCER_KEY` in `apps/traefik/.env.sops` equals `BOUNCER_KEY_TRAEFIK` in `apps/crowdsec/.env.sops`. Both decrypt to the same value via SOPS.                 |
| Traefik logs `middleware "crowdsec@file" does not exist` at startup          | Typo in `dynamic.yml` or YAML parse error                            | Run `docker exec traefik traefik healthcheck --ping`; check the `crowdsec:` middleware block in `dynamic.yml` parses cleanly.                                                  |
| Plugin logs `open /run/secrets/crowdsec_lapi_key: no such file or directory` | `secrets:` block missing or `.env` doesn't have CROWDSEC_BOUNCER_KEY | Verify `apps/traefik/.env.sops` decrypts to a `.env` containing `CROWDSEC_BOUNCER_KEY=...` and the traefik service has `secrets: [crowdsec_lapi_key]`.                         |
| `handleStreamCache:updated` never appears in Traefik logs                    | Stream sync failing silently                                         | Check `docker exec traefik wget -qO- -S --header "X-Api-Key: $(cat /run/secrets/crowdsec_lapi_key)" http://crowdsec:8080/v1/decisions/stream?startup=true` for a 200 response. |

## Visibility Options

CrowdSec itself has no self-hosted web UI. The `cscli dashboard setup` command that used to ship a local Metabase instance was deprecated in 1.6 and removed in 1.7 — don't go looking for it. Realistic options:

**1. Web UI sidecar (deployed in this stack).** [TheDuffman85/crowdsec-web-ui](https://github.com/TheDuffman85/crowdsec-web-ui) at `crowdsec.jaw.dev`. Full dashboard — alerts, decisions, attacker geo-IP, AS info — behind google-auth. Runs as the `crowdsec-web-ui` service in this compose, talks to LAPI with watcher credentials. **This is the primary GUI.**

**2. CLI.** `cscli decisions list`, `cscli alerts list`, `cscli metrics`. Useful for scripts and one-off queries.

**3. Homepage widget.** [Homepage](https://gethomepage.dev/widgets/services/crowdsec/) has a built-in CrowdSec widget that hits LAPI for live decision/alert counts. A few lines of YAML in `apps/homepage/`. Good for at-a-glance numbers on the main dashboard.

**4. CrowdSec Console (hosted, free tier).** [console.crowdsec.net](https://console.crowdsec.net). Enroll the instance by adding `ENROLL_KEY=<key>` to `apps/crowdsec/.env.sops` and redeploying. Alert metadata leaves the homelab; logs and secrets stay local. Skip if you're happy with the local sidecar — it covers the same use cases.

**5. Grafana + Prometheus.** The agent already exposes Prometheus metrics on `:6060` (293 metric series — `cs_active_decisions`, bucket pours, parser stats, etc.). Pair with [Grafana dashboard 21419](https://grafana.com/grafana/dashboards/21419-crowdsec-metrics/) if you stand up Grafana for other monitoring later. The official `crowdsecurity/grafana-dashboards` repo is stale (last update 2024-03), so dashboard 21419 is the better source.

## File Layout

```
apps/crowdsec/
├── docker-compose.yml   # agent + crowdsec-web-ui sidecar
├── acquis.yaml          # tells agent to tail /var/log/traefik/access.log
├── docker-cd.yml        # rolling_update: false (stateful — no parallel instances)
├── .env.sops            # BOUNCER_KEY_TRAEFIK, CROWDSEC_WEB_UI_USER/PASSWORD, optional ENROLL_KEY
└── README.md            # this file
```

### Services in this stack

- **`crowdsec`** — the agent. Reads Traefik logs, runs scenarios, exposes LAPI on `:8080` over the `traefik` Docker network. Backed by SQLite at `/home/jaw/data/crowdsec/db/`.
- **`crowdsec-web-ui`** — sidecar dashboard ([TheDuffman85/crowdsec-web-ui](https://github.com/TheDuffman85/crowdsec-web-ui)). Authenticates to LAPI with watcher credentials, serves a web UI at `:3000`, routed to `crowdsec.jaw.dev` through Traefik with google-auth. Waits for the agent's healthcheck (`depends_on: service_healthy`) before starting.

Traefik wiring lives in two files under `apps/traefik/`:

- `docker-compose.yml`
  - `--experimental.plugins.bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin`
  - `--experimental.plugins.bouncer.version=v1.6.0`
  - `crowdsec@file` in the `websecure` default middleware chain
  - `secrets.crowdsec_lapi_key` block sourced from `CROWDSEC_BOUNCER_KEY` env (in `.env`)
- `dynamic.yml`
  - `http.middlewares.crowdsec.plugin.bouncer` — full middleware config (stream mode, CF ranges, `crowdsecLapiKeyFile: /run/secrets/crowdsec_lapi_key`)

Host data: `/home/jaw/data/crowdsec/{db,config}` (SQLite + hub state, backed up by Backrest at 4:30 AM daily).

## Backup

Daily Backrest snapshot at 4:30 AM (`apps/backrest/config/config.json`, plan id `crowdsec`).

- Whole `/home/jaw/data/crowdsec/` is captured, with raw `crowdsec.db{,-wal,-shm}` excluded.
- A pre-hook runs `sqlite3 ... .backup` into `/source/crowdsec/.crowdsec.bak` for crash-consistent DB capture.
- Post-hook removes the `.bak`.

Restore (after wiping local state):

```bash
docker exec backrest restic -r /repos/crowdsec restore latest --target /tmp/restore
cd ~/home-ops/apps/crowdsec && docker compose stop
rsync -a --delete /tmp/restore/source/crowdsec/ /home/jaw/data/crowdsec/ --exclude '.crowdsec.bak'
docker exec backrest sqlite3 /home/jaw/data/crowdsec/db/crowdsec.db ".restore /tmp/restore/source/crowdsec/.crowdsec.bak"
rm -f /home/jaw/data/crowdsec/db/crowdsec.db-wal /home/jaw/data/crowdsec/db/crowdsec.db-shm
docker compose up -d
```

Loss of the DB is non-fatal: the bouncer re-registers from `BOUNCER_KEY_TRAEFIK` on agent boot, and the community blocklist re-syncs within ~10 min. The valuable part is custom whitelists and accumulated local decisions.

## Future Phases (Deferred)

Things explicitly out of scope for the current Phase 1 setup, in rough order of value:

- **AppSec / WAF.** CrowdSec ships an inline request-inspection engine (SQLi, XSS, deserialization, etc.) separate from the log-parsing scenarios. Enabling it adds `crowdsecAppsecEnabled: true` to the middleware and exposes a second port (`:7422`) on the agent. Per-request CPU cost and a real false-positive tuning burden; revisit after the behavioral layer is trusted.
- **Captcha middleware.** Instead of straight 403 on detection, present an hCaptcha challenge. Better UX for borderline decisions on auth pages; needs a captcha provider account.
- **Cloudflare edge bouncer (`cs-cloudflare-bouncer`).** Pushes bans into CF's IP-list / WAF rules so attackers are blocked at the edge and never reach origin. Needs a CF API token with WAF scope. CF Free tier IP-list quota is 10k entries (community blocklist is larger); usually configured to sync only high-severity decisions.
- **Linux / SSH collection + host firewall bouncer.** Add `crowdsecurity/linux` + `crowdsecurity/sshd` to detect SSH brute-force from host auth log, and `cs-firewall-bouncer` to enforce bans via iptables/nftables. Currently relying on `fail2ban` for SSH (see `docs/security.md`).
- **Self-hosted dashboard with custom queries.** Vanilla Metabase pointed at the SQLite DB — discussed in _Visibility Options_ above.

## Deploy Notes

A few things worth knowing if you're re-deploying or migrating this:

- **Yaegi plugin downloads on first Traefik start.** The bouncer plugin is fetched from GitHub the first time Traefik boots with the `--experimental.plugins.bouncer.*` flags. ~30s extra start time on a fresh host; cached after that. If the host has no internet, Traefik won't start.
- **Deploy order on a fresh setup.** If you're introducing CrowdSec on an already-running stack: deploy `apps/crowdsec/` first and wait for the agent to be healthy, THEN add `crowdsec@file` to the websecure default chain in `apps/traefik/docker-compose.yml`. Otherwise expect a transient window of `middleware does not exist` errors and 404s on every router. With `@file` middleware, the only requirement is that the `dynamic.yml` middleware block exists; the agent itself just needs to be reachable on the network for the plugin to authenticate.
- **`forwardedHeadersTrustedIPs` and Cloudflare's ranges.** Cloudflare publishes their IP list at [cloudflare.com/ips/](https://www.cloudflare.com/ips/). When CF adds a new range, update this list in `dynamic.yml` AND the matching `cloudflare-only` list also in `dynamic.yml` AND the `forwardedHeaders.trustedIPs` flags in `apps/traefik/docker-compose.yml`. (Same change in three places — annoying but explicit.)
