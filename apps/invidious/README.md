# Invidious

Self-hosted YouTube frontend. Private instance behind `oauth2-admin@file`.

## Services

| Service               | Purpose                                                                                          |
| --------------------- | ------------------------------------------------------------------------------------------------ |
| `invidious`           | Web UI + API                                                                                     |
| `invidious-companion` | Deno sidecar — handles signature decryption, DASH manifests, PO-tokens. Replaced inv-sig-helper. |
| `invidious-db`        | Postgres 16 for user accounts, subscriptions, and watch history                                  |

## Caveats

YouTube actively blocks third-party frontends. Two failure modes to expect:

- **Bot detection on the residential IP.** If the home internet IP gets rate-limited or flagged, videos return 403/429. Symptoms: thumbnails load but playback fails. There is no fix beyond waiting it out.
- **Player-JS rotation.** YouTube rotates the player scripts every 1–2 weeks; `invidious-companion` typically follows within a day. When playback breaks, bump the `quay.io/invidious/invidious-companion` digest (Renovate handles this automatically).

## Recommended: nightly restart

Upstream docs recommend restarting the Invidious container daily to clear caches and pick up companion's latest YouTube workarounds. Add this to the host's root crontab:

```cron
0 5 * * * /usr/bin/docker restart invidious invidious-companion >/dev/null 2>&1
```

Do not route this through `gluetun` — datacenter VPN IPs are blocked harder than residential.

## Config

Non-secret config lives in `config/config.yml`. Secrets (`INVIDIOUS_HMAC_KEY`, DB password) live in `.env.sops` and override config values via Invidious's `INVIDIOUS_*` env-var convention (double-underscore for nested keys, e.g. `INVIDIOUS_DB__PASSWORD`).

## Backup

`invidious-db` is dumped nightly by Backrest at 4:40 AM. Postgres is dumped via `pg_dump` from a hook; the raw `data/` dir is excluded.
