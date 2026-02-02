.PHONY: help bootstrap network traefik doco-cd status logs deploy down pull clean ps

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if exists
-include .env
export

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Bootstrap
bootstrap: network traefik doco-cd ## Bootstrap full stack

network: ## Create traefik network
	@docker network inspect traefik >/dev/null 2>&1 || docker network create traefik
	@echo "✓ traefik network ready"

traefik: network ## Start traefik
	@docker compose -f infrastructure/traefik/docker-compose.yml up -d
	@echo "✓ traefik started"

doco-cd: network ## Start doco-cd
	@docker compose -f infrastructure/doco-cd/docker-compose.yml up -d
	@echo "✓ doco-cd started"

# Operations
status: ## Show running containers
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

ps: status ## Alias for status

logs: ## Tail doco-cd logs
	@docker logs -f doco-cd

logs-traefik: ## Tail traefik logs
	@docker logs -f traefik

deploy: ## Deploy specific app (APP=apps/myapp)
	@test -n "$(APP)" || (echo "Usage: make deploy APP=apps/myapp" && exit 1)
	@docker compose -f $(APP)/docker-compose.yml up -d
	@echo "✓ $(APP) deployed"

down: ## Stop specific app (APP=apps/myapp)
	@test -n "$(APP)" || (echo "Usage: make down APP=apps/myapp" && exit 1)
	@docker compose -f $(APP)/docker-compose.yml down
	@echo "✓ $(APP) stopped"

restart: ## Restart specific app (APP=apps/myapp)
	@test -n "$(APP)" || (echo "Usage: make restart APP=apps/myapp" && exit 1)
	@docker compose -f $(APP)/docker-compose.yml restart
	@echo "✓ $(APP) restarted"

pull: ## Pull latest images for all apps
	@for f in $$(find . -name 'docker-compose.yml' -not -path './.claude/*'); do \
		echo "Pulling: $$f"; \
		docker compose -f $$f pull; \
	done

up-all: ## Start all apps manually
	@for f in $$(find . -name 'docker-compose.yml' -not -path './.claude/*'); do \
		echo "Starting: $$f"; \
		docker compose -f $$f up -d; \
	done

down-all: ## Stop all apps
	@for f in $$(find . -name 'docker-compose.yml' -not -path './.claude/*'); do \
		echo "Stopping: $$f"; \
		docker compose -f $$f down; \
	done

clean: down-all ## Stop all and prune
	@docker system prune -f
	@echo "✓ cleaned"

# Debug
shell: ## Shell into doco-cd container
	@docker exec -it doco-cd sh

health: ## Check doco-cd health
	@curl -s http://localhost:8080/v1/health | jq . || echo "doco-cd not responding"
