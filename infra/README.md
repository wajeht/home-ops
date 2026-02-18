# Infrastructure

Core services that other apps depend on.

| Service                 | Type  | Notes                       |
| ----------------------- | ----- | --------------------------- |
| [docker-cd](docker-cd/) | infra | GitOps deployer             |
| [caddy](caddy/)         | infra | Reverse proxy + auth portal |

Managed via `./scripts/home-ops.sh`:

- `install` — first-time deploy of all infra + apps
- `update-infra` — pull latest and redeploy caddy + docker-cd
- `update-infra-force` — same but force-recreate containers
