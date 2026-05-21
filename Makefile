.DEFAULT_GOAL := help

.PHONY: setup install install-fresh uninstall update update-force status relogin format lint push fix-git images images-prune clean update-submodules resources nfs-mount nfs-unmount nfs-persist nfs-unpersist nfs-status sata-mount sata-unmount sata-persist sata-unpersist sata-status help

setup:
	@./scripts/home-ops.sh setup

install:
	@./scripts/home-ops.sh install

install-fresh:
	@./scripts/home-ops.sh install-fresh

uninstall:
	@./scripts/home-ops.sh uninstall

update:
	@./scripts/home-ops.sh update-infra

update-force:
	@./scripts/home-ops.sh update-infra-force

status:
	@./scripts/home-ops.sh status

relogin:
	@./scripts/home-ops.sh relogin

format:
	@npx oxfmt "**/*.{yml,yaml,md,json}" '!apps/adguard/**'
	@shfmt -w -i 0 -ci scripts/*.sh

lint:
	@./scripts/lint.sh

push:
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) resources
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

update-submodules:
	@git submodule update --remote
	@git add -A
	@git commit -m "chore: update submodules"
	@git push

fix-git:
	@git rm -r --cached . -f
	@git add .
	@git commit -m "untrack files in .gitignore"

images:
	@./scripts/home-ops.sh images

images-prune:
	@./scripts/home-ops.sh images prune

clean:
	@docker system prune -a -f
	@docker volume prune -f
	@docker network prune -f

resources:
	@./scripts/check-resources.sh

nfs-mount:
	@./scripts/home-ops.sh nfs mount

nfs-unmount:
	@./scripts/home-ops.sh nfs unmount

nfs-persist:
	@./scripts/home-ops.sh nfs persist

nfs-unpersist:
	@./scripts/home-ops.sh nfs unpersist

nfs-status:
	@./scripts/home-ops.sh nfs status

sata-mount:
	@./scripts/home-ops.sh sata mount

sata-unmount:
	@./scripts/home-ops.sh sata unmount

sata-persist:
	@./scripts/home-ops.sh sata persist

sata-unpersist:
	@./scripts/home-ops.sh sata unpersist

sata-status:
	@./scripts/home-ops.sh sata status

help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
