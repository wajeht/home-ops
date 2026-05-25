# Renovate CE (Self-Hosted)

Mend Renovate Community Edition — auto-updates dependencies across all repos.

## GitHub App

- **App:** [wajeht-renovate](https://github.com/settings/apps/wajeht-renovate)
- **App ID:** 2825559
- **Platform:** github.com
- **Installed on:** All repositories (@wajeht)

## URLs

- **Dashboard:** https://renovate.jaw.dev (behind OAuth)
- **Webhook:** https://renovate.jaw.dev/webhook
- **Health:** https://renovate.jaw.dev/health

## Secrets (.env.sops)

| Variable                  | Description                                   |
| ------------------------- | --------------------------------------------- |
| `MEND_RNV_GITHUB_APP_KEY` | GitHub App private key (PEM, `\n` escaped)    |
| `MEND_RNV_WEBHOOK_SECRET` | Webhook secret (must match GitHub App config) |
| `MEND_RNV_LICENSE_KEY`    | Mend Community Edition license key            |
| `GITHUB_COM_TOKEN`        | PAT for changelog fetching                    |

```bash
# View secrets
sops apps/renovate/.env.sops

# Edit secrets
sops apps/renovate/.env.sops
```

## Setup from scratch

1. Create GitHub App at https://github.com/settings/apps/new
   - Webhook URL: `https://renovate.jaw.dev/webhook`
   - Repository permissions: Administration (read), Checks (read/write), Codespaces metadata (read), Commit statuses (read/write), Contents (read/write), Dependabot alerts (read), Issues (read/write), Metadata (read), Pull requests (read/write), Workflows (read/write)
   - Organization permissions: Members (read)
   - Events: Fork, Issues, Pull request, Push, Repository
2. Generate private key from app settings page
3. Install app on account (all repos)
4. Register for free license key at https://www.mend.io/mend-renovate-community/
5. Create `.env` with secrets, encrypt with `sops -e .env > .env.sops`

## Notes

- Container runs as `uid=12021` — data dir needs matching ownership
- SQLite DB persists at `~/data/renovate/renovate.db`
- Scheduler runs 3x daily (12am, 8am, 6pm UTC)
- Webhooks trigger immediate re-scan on push/PR events
