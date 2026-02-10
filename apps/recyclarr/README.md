# Recyclarr

Auto-syncs [TRaSH Guide](https://trash-guides.info/) quality profiles, custom formats, and scores into Radarr/Sonarr.

## Secrets

API keys stored in `.enc.env` (SOPS encrypted), auto-decrypted by docker-cd. Config at `~/data/recyclarr/recyclarr.yml` references them via `!env_var`.

```bash
# Edit secrets
sops apps/recyclarr/.enc.env
```

## Server Config

`~/data/recyclarr/recyclarr.yml` — main config with TRaSH templates (mounted to `/config`).

## Manual Test

```bash
docker compose -f apps/recyclarr/docker-compose.yml run --rm recyclarr sync
```

## Updating Config

Edit `~/data/recyclarr/recyclarr.yml` on the server. Available templates: https://recyclarr.dev/wiki/yaml/config-reference/
