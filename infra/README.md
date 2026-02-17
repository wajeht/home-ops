# Infrastructure

Core services that other apps depend on.

| Service                 | Type      | Notes                                                     |
| ----------------------- | --------- | --------------------------------------------------------- |
| [docker-cd](docker-cd/) | real      | GitOps deployer, manually deployed via `update-infra`     |
| [caddy](../apps/caddy/) | app stack | Reverse proxy + auth portal, auto-discovered by docker-cd |

Caddy lives in `apps/` so docker-cd auto-discovers it with the rest of the app stacks.
