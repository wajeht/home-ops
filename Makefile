.DEFAULT_GOAL := help

.PHONY: setup install install-fresh uninstall update update-force status relogin format lint validate push fix-git clean help

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

## update: Redeploy infra (caddy + docker-cd)
update:
	@./scripts/home-ops.sh update-infra

## update-force: Force-recreate infra containers (caddy + docker-cd)
update-force:
	@./scripts/home-ops.sh update-infra-force

## status: Show containers, mounts, and disk usage
status:
	@./scripts/home-ops.sh status

## relogin: Refresh docker registry credentials
relogin:
	@./scripts/home-ops.sh relogin

## format: Format YAML/Markdown/JSON files
format:
	@npx oxfmt "**/*.{yml,yaml,md,json}" '!apps/adguard/**'

## lint: Check formatting
lint:
	@npx oxfmt --check "**/*.{yml,yaml,md,json}" '!apps/adguard/**'

## validate: Validate encryption + docker compose files
validate: lint
	@fail=0; \
	tmp_env=$$(mktemp); \
	tmp_caddy=$$(mktemp); \
	trap 'rm -f "$$tmp_env" "$$tmp_caddy"' EXIT; \
	for f in $$(find . -name '.env.sops' -not -path './.git/*' -not -path './apps/adguard/*'); do \
		if ! grep -q 'sops_mac=' "$$f"; then \
			echo "ERROR: $$f is not SOPS-encrypted"; \
			fail=1; \
		fi; \
	done; \
	for f in $$(find . -name 'docker-compose.yml' -not -path './.git/*' -not -path './apps/adguard/*'); do \
		if ! docker compose --env-file "$$tmp_env" -f "$$f" config -q 2>/dev/null; then \
			echo "ERROR: $$f is invalid"; \
			fail=1; \
		fi; \
	done; \
	cat "$$PWD/infra/caddy/Caddyfile" > "$$tmp_caddy"; \
	printf '\nvalidate.local {\n\timport public\n\treverse_proxy 127.0.0.1:8080\n}\n' >> "$$tmp_caddy"; \
	if ! docker run --rm \
		-v "$$tmp_caddy:/etc/caddy/Caddyfile:ro" \
		-v "$$PWD/infra/caddy/ui:/etc/caddy/ui:ro" \
		ghcr.io/wajeht/docker-cd-caddy:sha-1e84728 \
		caddy adapt --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then \
		echo "ERROR: infra/caddy/Caddyfile failed caddy adapt validation"; \
		fail=1; \
	fi; \
	exit $$fail

## push: Format, validate, commit, and push changes
push:
	@$(MAKE) format
	@$(MAKE) validate
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

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
