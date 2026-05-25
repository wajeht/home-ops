# Infrastructure

Core services that other apps depend on.

| Service                               | Type  | Notes              |
| ------------------------------------- | ----- | ------------------ |
| [docker-cd](docker-cd/)               | infra | GitOps deployer    |
| [traefik](traefik/)                   | infra | Reverse proxy      |
| [oauth2-proxy](../apps/oauth2-proxy/) | infra | OAuth forward-auth |

Managed via `./scripts/setup.sh`:

- `install` — first-time deploy of all infra + apps
- `update-infra` — pull latest and redeploy docker-cd
- `update-infra-force` — same but force-recreate docker-cd
