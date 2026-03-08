.DEFAULT_GOAL := help

.PHONY: setup install install-fresh uninstall update update-force status relogin borgmatic-init borgmatic-backup format lint push fix-git clean update-submodules help

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

## borgmatic-init: Initialize borg repos for all borgmatic containers
borgmatic-init:
	@./scripts/home-ops.sh borgmatic-init

## borgmatic-backup: Run backup on all borgmatic containers
## borgmatic-backup-<app>: Run backup for single app (e.g. make borgmatic-backup-homeassistant)
borgmatic-backup:
	@./scripts/home-ops.sh borgmatic-backup

borgmatic-backup-%:
	@./scripts/home-ops.sh borgmatic-backup $*

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

## clean: Prune docker system objects
clean:
	@docker system prune -a -f
	@docker volume prune -f
	@docker network prune -f

## help: Show available make targets
help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
