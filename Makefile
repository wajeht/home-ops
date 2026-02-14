INFRA_LINKS = traefik google-auth

.PHONY: link unlink push fix-git clean help

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

push:
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
