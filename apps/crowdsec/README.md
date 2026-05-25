# CrowdSec

CrowdSec bans malicious IPs at Traefik before they reach apps. The agent parses Traefik's access log, runs detection scenarios, and pulls a community blocklist of known-bad IPs. A Yaegi plugin inside Traefik queries the agent's local API on every request and returns 403 for banned IPs.

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

## Real Client IP

Bans key off `CF-Connecting-IP`, not the immediate source IP (which is always Cloudflare). The middleware's `forwardedHeadersCustomName` is set to `CF-Connecting-IP` and `forwardedHeadersTrustedIPs` lists the same CF ranges already trusted elsewhere in the stack.

## API Key Handling

The bouncer API key is stored in `apps/traefik/.env.sops` as `CROWDSEC_BOUNCER_KEY` (encrypted) and in `apps/crowdsec/.env.sops` as `BOUNCER_KEY_TRAEFIK` — same value, two stacks. The agent reads it via the `BOUNCER_KEY_*` env-var convention to auto-register a bouncer named `traefik` at boot. Traefik consumes it via a Docker Compose secret (`secrets.environment: CROWDSEC_BOUNCER_KEY`) which is mounted at `/run/secrets/crowdsec_lapi_key` (tmpfs) and read by the middleware via `crowdsecLapiKeyFile`. The key never appears in any committed YAML file.

Internal LAN ranges (`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) are in `clientTrustedIPs` — they can never be banned.

## Pre-Deploy Setup

Create the host data directories before first deploy:

```bash
mkdir -p /home/jaw/data/crowdsec/{db,config}
```

The bouncer API key (`BOUNCER_KEY_TRAEFIK`) lives in `apps/crowdsec/.env.sops` and is auto-registered as a bouncer at agent startup via the `BOUNCER_KEY_*` env var convention.

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

| Symptom                                          | Cause                                               | Fix                                                                                                               |
| ------------------------------------------------ | --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Traefik refuses to start, log mentions plugin    | Yaegi can't fetch plugin (no internet, GitHub down) | Revert the `--experimental.plugins.*` lines in `apps/traefik/docker-compose.yml`, redeploy.                       |
| LAPI unreachable, requests still pass            | Plugin default `defaultDecision=allow`              | Working as designed — fail-open avoids self-lockout when CrowdSec crashes.                                        |
| Legit user banned (false positive)               | A behavioral scenario over-fired                    | `cscli decisions delete --ip <ip>` and add to the whitelist file above.                                           |
| Agent banning Cloudflare IPs                     | Real-client header not extracted                    | Check `forwardedHeadersCustomName=CF-Connecting-IP` label on the crowdsec container.                              |
| Bouncer shows `invalid` in `cscli bouncers list` | Key mismatch                                        | Confirm `BOUNCER_KEY_TRAEFIK` is identical in `apps/crowdsec/.env.sops` and used by the Traefik middleware label. |

## Web Dashboard (Optional)

To enroll the instance in [console.crowdsec.net](https://console.crowdsec.net) for a hosted dashboard:

1. Create an account, generate an enrollment key.
2. Add `ENROLL_KEY=<key>` to `apps/crowdsec/.env.sops` (`sops apps/crowdsec/.env.sops`).
3. Redeploy. The agent enrolls on next boot.

## File Layout

```
apps/crowdsec/
├── docker-compose.yml   # agent + bouncer middleware labels
├── acquis.yaml          # tells agent to tail /var/log/traefik/access.log
└── .env.sops            # BOUNCER_KEY_TRAEFIK, optional ENROLL_KEY
```

Traefik wiring:

- `apps/traefik/docker-compose.yml`
  - `--experimental.plugins.bouncer.modulename=github.com/maxlerebourg/crowdsec-bouncer-traefik-plugin`
  - `--experimental.plugins.bouncer.version=v1.6.0`
  - `crowdsec@file` in the `websecure` default middleware chain
  - `secrets.crowdsec_lapi_key` sourced from `CROWDSEC_BOUNCER_KEY` env
- `apps/traefik/dynamic.yml`
  - `http.middlewares.crowdsec.plugin.bouncer` — full middleware config (stream mode, CF ranges, key file path)

Host data: `/home/jaw/data/crowdsec/{db,config}` (SQLite + hub state, backed up by Backrest).

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
