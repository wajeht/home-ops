# CrowdSec

Intrusion detection + Traefik bouncer. No web UI — use CLI.

## Common commands

```bash
# View alerts
docker exec crowdsec-crowdsec-1 cscli alerts list

# View active bans/decisions
docker exec crowdsec-crowdsec-1 cscli decisions list

# Parsing/bucket metrics
docker exec crowdsec-crowdsec-1 cscli metrics

# List installed collections
docker exec crowdsec-crowdsec-1 cscli collections list

# List bouncers
docker exec crowdsec-crowdsec-1 cscli bouncers list

# Manually ban an IP
docker exec crowdsec-crowdsec-1 cscli decisions add --ip 1.2.3.4 --reason "manual ban"

# Unban an IP
docker exec crowdsec-crowdsec-1 cscli decisions delete --ip 1.2.3.4
```

## Architecture

- Reads Traefik access logs via shared `traefik-logs` volume
- Acquisition config: `acquis.yaml` → `/etc/crowdsec/acquis.d/traefik.yaml`
- Bouncer key in `.enc.env` → Traefik bouncer plugin authenticates with it
- Prometheus metrics enabled on `:6060` (for Grafana, currently disabled)

## Collections

- `crowdsecurity/traefik` — Traefik log parser + scenarios
- `crowdsecurity/http-cve` — CVE exploit detection
- `crowdsecurity/http-dos` — HTTP flood/DoS detection

## Monitoring

Grafana dashboards available in `apps/grafana/` (currently `ignore: true`).
