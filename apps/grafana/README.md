# Grafana + Prometheus (CrowdSec Monitoring)

Currently disabled via `docker-cd.yml` → `ignore: true`.

## Enable

Set `ignore: false` in `apps/grafana/docker-cd.yml` and push. docker-cd will auto-deploy.

## Fix data dir permissions (first deploy only)

```bash
sudo chown -R 65534:65534 ~/data/grafana/prometheus
sudo chown -R 472:472 ~/data/grafana/data
```

## CrowdSec CLI (no UI needed)

```bash
docker compose -p crowdsec exec crowdsec cscli alerts list
docker compose -p crowdsec exec crowdsec cscli decisions list
docker compose -p crowdsec exec crowdsec cscli metrics
```

## Update Grafana admin password

```bash
SOPS_AGE_KEY_FILE=~/.sops/age-key.txt sops apps/grafana/.enc.env
```

## Dashboards

4 official CrowdSec dashboards auto-provisioned from `dashboards/`:
- Crowdsec Overview
- Crowdsec Details per instance
- Crowdsec Insight
- LAPI Metrics
