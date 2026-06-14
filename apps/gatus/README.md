# Gatus

[Gatus](https://github.com/TwiN/gatus) is the health dashboard at `gatus.jaw.dev`. It probes critical services on the `traefik` network and sends ntfy alerts when checks fail.

## Layout

```
apps/gatus/
├── docker-compose.yml     # includes x-docker-cd.rolling_update: false
├── config/
│   └── config.yaml        # endpoints + alerting
└── httpcheck              # static binary used for container healthcheck
```

`config/` is mounted read-only at `/config`. Gatus merges every `*.yaml` and `*.yml` file in that directory, so the config can be split as it grows.

SQLite history lives at `/home/jaw/data/gatus/gatus.db`.

## Adding an Endpoint

Edit `config/config.yaml` and add a block under `endpoints:`. Use the service's container name and internal port — Gatus is on the `traefik` network and resolves them directly.

```yaml
- name: MyApp
  group: Tools
  url: http://myapp:8080/healthz
  interval: 1m
  conditions:
    - "[STATUS] == 200"
    - "[RESPONSE_TIME] < 3000"
  alerts:
    - type: ntfy
```

Gatus hot-reloads on config changes, so a `docker-cd` deploy is enough — no restart needed.

### Endpoint Types

| Type | URL form                   | Use when                                              |
| ---- | -------------------------- | ----------------------------------------------------- |
| HTTP | `http://service:port/path` | App exposes an HTTP endpoint on the `traefik` network |
| TCP  | `tcp://host:port`          | App is on another network or HTTP isn't suitable      |
| ICMP | `icmp://host`              | Plain reachability check                              |
| DNS  | `dns://server`             | Validate a DNS record resolves                        |

For apps running on a different host (e.g. AdGuard on `pi@192.168.4.181`), use a TCP probe against the host's published port: `tcp://<host-ip>:<port>`.

### Host Header Quirks

Some apps reject requests whose `Host` header doesn't match an allow-list (Homepage `HOMEPAGE_ALLOWED_HOSTS`, SABnzbd `HOST_WHITELIST_ENTRIES`, Home Assistant `trusted_proxies`). Spoof the header so the probe passes:

```yaml
url: http://homepage:3000
headers:
  Host: home.jaw.dev
```

## Alerting

Alerts go to the self-hosted ntfy on the `gatus` topic (matches the per-app-topic pattern used by `ddns-updater`, backrest plans, etc.). Subscribe via the ntfy app at `https://ntfy.jaw.dev/gatus`.

Defaults (set under `alerting.ntfy.default-alert`):

- `failure-threshold: 3` — alert after three consecutive failures
- `success-threshold: 2` — resolve after two consecutive successes
- `send-on-resolved: true`

To opt an endpoint out of alerting, drop its `alerts:` block.

## httpcheck Pattern

Gatus' image is `FROM scratch` — no shell, no `wget`, no `curl`. The container healthcheck uses a static Go binary (`httpcheck`) mounted into the container:

```yaml
volumes:
  - ./httpcheck:/httpcheck:ro
healthcheck:
  test: ["CMD", "/httpcheck", "http://127.0.0.1:8080/health"]
```

This is the canonical example referenced from [adding-apps.md](adding-apps.md#health-checks) for any scratch/minimal image.

## Useful Endpoints

- Dashboard: `https://gatus.jaw.dev`
- Prometheus metrics: `https://gatus.jaw.dev/metrics` (auth-gated)
- Liveness: `http://gatus:8080/health` (in-network only)
