# CrowdSec

Intrusion detection + Traefik bouncer. No web UI — use CLI.

## Common commands

```bash
# View alerts
docker compose -p crowdsec exec crowdsec cscli alerts list

# View active bans/decisions
docker compose -p crowdsec exec crowdsec cscli decisions list

# Parsing/bucket metrics
docker compose -p crowdsec exec crowdsec cscli metrics

# List installed collections
docker compose -p crowdsec exec crowdsec cscli collections list

# List bouncers
docker compose -p crowdsec exec crowdsec cscli bouncers list

# Manually ban an IP
docker compose -p crowdsec exec crowdsec cscli decisions add --ip 1.2.3.4 --reason "manual ban"

# Unban an IP
docker compose -p crowdsec exec crowdsec cscli decisions delete --ip 1.2.3.4
```

## Architecture

- Reads Traefik access logs via shared `traefik-logs` volume
- Acquisition config: `acquis.yaml` → `/etc/crowdsec/acquis.d/traefik.yaml`
- Bouncer key in `.env.sops` → Traefik bouncer plugin authenticates with it
- Prometheus metrics enabled on `:6060` (for Grafana, currently disabled)

## Collections

- `crowdsecurity/traefik` — Traefik log parser + scenarios
- `crowdsecurity/http-cve` — CVE exploit detection
- `crowdsecurity/http-dos` — HTTP flood/DoS detection

## Monitoring

Grafana dashboards available in `apps/grafana/` (currently `ignore_deployment: true`).
