# Infrastructure

Core services that other apps depend on.

| Service                 | Type  | Notes                                                             |
| ----------------------- | ----- | ----------------------------------------------------------------- |
| [docker-cd](docker-cd/) | infra | GitOps deployer, manually deployed via `update-infra`             |
| [caddy](caddy/)         | infra | Reverse proxy + auth portal, manually deployed via `update-infra` |

Infra stacks are deployed manually with `./scripts/home-ops.sh update-infra`.
