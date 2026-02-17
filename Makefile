INFRA_LINKS = caddy

.PHONY: format lint validate link unlink push fix-git clean help

format:
	@npx oxfmt "**/*.{yml,yaml,md,json}" '!apps/adguard/**'

lint:
	@npx oxfmt --check "**/*.{yml,yaml,md,json}" '!apps/adguard/**'

link:
	@for app in $(INFRA_LINKS); do \
		if [ -L infra/$$app ]; then \
			echo "already linked: infra/$$app"; \
		else \
			ln -s ../apps/$$app infra/$$app && echo "linked: infra/$$app -> apps/$$app"; \
		fi \
	done

unlink:
	@for app in $(INFRA_LINKS); do \
		if [ -L infra/$$app ]; then \
			rm infra/$$app && echo "unlinked: infra/$$app"; \
		else \
			echo "not linked: infra/$$app"; \
		fi \
	done

validate: lint
	@fail=0; \
	tmp_env=$$(mktemp); \
	trap 'rm -f "$$tmp_env"' EXIT; \
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
	exit $$fail

push: validate
	@git add -A
	@curl -s https://commit.jaw.dev/ | sh -s -- --no-verify
	@git push --no-verify

fix-git:
	@git rm -r --cached . -f
	@git add .
	@git commit -m "untrack files in .gitignore"

clean:
	@docker system prune -a -f
	@docker volume prune -f
	@docker network prune -f

help:
	@grep -E '^## ' Makefile | sed 's/## /  /'
