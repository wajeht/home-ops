.DEFAULT_GOAL := help

.PHONY: setup install install-fresh uninstall update update-force status relogin format lint push fix-git images images-prune clean update-submodules resources nfs-mount nfs-unmount nfs-persist nfs-unpersist nfs-status sata-mount sata-unmount sata-persist sata-unpersist sata-status help

## setup: Create all data directories
setup:
	@./scripts/home-ops.sh setup

## install: Deploy core infra and bootstrap docker-cd
install:
	@./scripts/home-ops.sh install

## install-fresh: Reset docker-cd state then deploy infra (forces full app reconcile)
install-fresh:
	@./scripts/home-ops.sh install-fresh

## uninstall: Remove all stacks and cleanup
uninstall:
	@./scripts/home-ops.sh uninstall

## update: Pull latest and redeploy docker-cd
update:
	@./scripts/home-ops.sh update-infra

## update-force: Pull latest and force-recreate docker-cd
update-force:
	@./scripts/home-ops.sh update-infra-force

## status: Show containers, mounts, and disk usage
status:
	@./scripts/home-ops.sh status

## relogin: Refresh docker registry credentials
relogin:
	@./scripts/home-ops.sh relogin

## format: Format YAML/Markdown/JSON/Shell files
format:
	@npx oxfmt "**/*.{yml,yaml,md,json}" '!apps/adguard/**'
	@shfmt -w -i 0 -ci scripts/*.sh

## lint: Check formatting + shellcheck + SOPS + hardening + compose syntax
lint:
	@./scripts/lint.sh

## push: Format, lint, commit, and push changes
push:
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) resources
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

## update-submodules: Pull latest for all submodules
update-submodules:
	@git submodule update --remote
	@git add -A
	@git commit -m "chore: update submodules"
	@git push

## fix-git: Rebuild index while respecting .gitignore
fix-git:
	@git rm -r --cached . -f
	@git add .
	@git commit -m "untrack files in .gitignore"

## images: Show unused Docker images and orphan volumes
## images-prune: Remove unused images (>7d) and orphan volumes
images:
	@./scripts/home-ops.sh images

images-prune:
	@./scripts/home-ops.sh images prune

## clean: Nuclear prune — removes ALL unused images, volumes, networks
clean:
	@docker system prune -a -f
	@docker volume prune -f
	@docker network prune -f

## resources: Report total CPU/memory limits across all stacks
resources:
	@./scripts/check-resources.sh

## nfs-mount: Mount NFS shares
nfs-mount:
	@./scripts/home-ops.sh nfs mount

## nfs-unmount: Unmount NFS shares
nfs-unmount:
	@./scripts/home-ops.sh nfs unmount

## nfs-persist: Add NFS mounts to fstab (survives reboot)
nfs-persist:
	@./scripts/home-ops.sh nfs persist

## nfs-unpersist: Remove NFS mounts from fstab
nfs-unpersist:
	@./scripts/home-ops.sh nfs unpersist

## nfs-status: Show NFS mount status
nfs-status:
	@./scripts/home-ops.sh nfs status

## sata-mount: Mount SATA drive
sata-mount:
	@./scripts/home-ops.sh sata mount

## sata-unmount: Unmount SATA drive
sata-unmount:
	@./scripts/home-ops.sh sata unmount

## sata-persist: Add SATA mount to fstab (survives reboot)
sata-persist:
	@./scripts/home-ops.sh sata persist

## sata-unpersist: Remove SATA mount from fstab
sata-unpersist:
	@./scripts/home-ops.sh sata unpersist

## sata-status: Show SATA mount status
sata-status:
	@./scripts/home-ops.sh sata status

## help: Show available make targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
