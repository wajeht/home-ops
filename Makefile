.DEFAULT_GOAL := help

.PHONY: setup install install-fresh uninstall update update-force status relogin format lint push fix-git images images-prune clean update-submodules resources nfs-mount nfs-unmount nfs-persist nfs-unpersist nfs-status sata-mount sata-unmount sata-persist sata-unpersist sata-status help

## setup                   Create data dirs and base setup
setup:
	@./scripts/home-ops.sh setup

## install                 Deploy infra and apps
install:
	@./scripts/home-ops.sh install

## install-fresh           Fresh install flow
install-fresh:
	@./scripts/home-ops.sh install-fresh

## uninstall               Remove stacks and cleanup
uninstall:
	@./scripts/home-ops.sh uninstall

## update                  Pull latest and redeploy docker-cd
update:
	@./scripts/home-ops.sh update-infra

## update-force            Force recreate docker-cd
update-force:
	@./scripts/home-ops.sh update-infra-force

## status                  Show services, mounts, and disk usage
status:
	@./scripts/home-ops.sh status

## relogin                 Refresh Docker login
relogin:
	@./scripts/home-ops.sh relogin

## format                  Format yaml, markdown, json, and shell
format:
	@npx oxfmt "**/*.{yml,yaml,md,json}" '!apps/adguard/**'
	@shfmt -w -i 0 -ci scripts/*.sh

## lint                    Run repo lint checks
lint:
	@./scripts/lint.sh

## push                    Format, lint, commit, and push
push:
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) resources
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

## update-submodules       Update git submodules
update-submodules:
	@git submodule update --remote
	@git add -A
	@git commit -m "chore: update submodules"
	@git push

## fix-git                 Re-add tracked files after gitignore changes
fix-git:
	@git rm -r --cached . -f
	@git add .
	@git commit -m "untrack files in .gitignore"

## images                  Show unused Docker images and volumes
images:
	@./scripts/home-ops.sh images

## images-prune            Remove old unused images and orphan volumes
images-prune:
	@./scripts/home-ops.sh images prune

## clean                   Prune Docker system, volumes, and networks
clean:
	@docker system prune -a -f
	@docker volume prune -f
	@docker network prune -f

## resources               Check container resource limits
resources:
	@./scripts/check-resources.sh

## nfs-mount               Mount NFS shares
nfs-mount:
	@./scripts/home-ops.sh nfs mount

## nfs-unmount             Unmount NFS shares
nfs-unmount:
	@./scripts/home-ops.sh nfs unmount

## nfs-persist             Add NFS mounts to fstab
nfs-persist:
	@./scripts/home-ops.sh nfs persist

## nfs-unpersist           Remove NFS mounts from fstab
nfs-unpersist:
	@./scripts/home-ops.sh nfs unpersist

## nfs-status              Show NFS mount status
nfs-status:
	@./scripts/home-ops.sh nfs status

## sata-mount              Mount SATA drive
sata-mount:
	@./scripts/home-ops.sh sata mount

## sata-unmount            Unmount SATA drive
sata-unmount:
	@./scripts/home-ops.sh sata unmount

## sata-persist            Add SATA mount to fstab
sata-persist:
	@./scripts/home-ops.sh sata persist

## sata-unpersist          Remove SATA mount from fstab
sata-unpersist:
	@./scripts/home-ops.sh sata unpersist

## sata-status             Show SATA mount status
sata-status:
	@./scripts/home-ops.sh sata status

## help                    Show this help
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
