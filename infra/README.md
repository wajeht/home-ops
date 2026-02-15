# Infrastructure

Core services that other apps depend on.

| Service                     | Type            | Notes                                                 |
| --------------------------- | --------------- | ----------------------------------------------------- |
| [docker-cd](docker-cd/)     | real            | GitOps deployer, manually deployed via `update-infra` |
| [traefik](traefik/)         | symlink → apps/ | Reverse proxy, auto-discovered by docker-cd           |
| [google-auth](google-auth/) | symlink → apps/ | Auth middleware, auto-discovered by docker-cd         |

Traefik and google-auth live in `apps/` so docker-cd auto-discovers them, but are symlinked here for organizational visibility.
