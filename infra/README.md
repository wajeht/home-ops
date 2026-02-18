# Infrastructure

Core services that other apps depend on.

| Service                     | Type  | Notes                     |
| --------------------------- | ----- | ------------------------- |
| [docker-cd](docker-cd/)     | infra | GitOps deployer           |
| [traefik](traefik/)         | infra | Reverse proxy             |
| [google-auth](google-auth/) | infra | Google OAuth forward-auth |

Managed via `./scripts/home-ops.sh`:

- `install` — first-time deploy of all infra + apps
- `update-infra` — pull latest and redeploy traefik + google-auth + docker-cd
- `update-infra-force` — same but force-recreate containers
