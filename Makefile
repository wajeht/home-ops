.PHONY: help bootstrap swarm-init network secrets traefik doco-cd status logs deploy down pull clean

SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env
export

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

# =============================================================================
# BOOTSTRAP
# =============================================================================
bootstrap: swarm-init network secrets traefik doco-cd ## Bootstrap full stack

swarm-init: ## Initialize Docker Swarm
	@docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || docker swarm init
	@echo "✓ swarm initialized"

network: ## Create traefik overlay network
	@docker network inspect traefik >/dev/null 2>&1 || \
		docker network create --driver overlay --attachable traefik
	@echo "✓ traefik network ready"

secrets: ## Create Docker secrets from .env
	@echo "Creating secrets..."
	@echo "$(GIT_ACCESS_TOKEN)" | docker secret create git_access_token - 2>/dev/null || true
	@echo "$(API_SECRET)" | docker secret create api_secret - 2>/dev/null || true
	@echo "$(WEBHOOK_SECRET)" | docker secret create webhook_secret - 2>/dev/null || true
	@echo "$(CF_DNS_API_TOKEN)" | docker secret create cf_dns_api_token - 2>/dev/null || true
	@echo "✓ secrets created (existing secrets skipped)"

secrets-update: ## Update secrets (removes and recreates)
	@echo "Updating secrets..."
	@docker secret rm git_access_token 2>/dev/null || true
	@docker secret rm api_secret 2>/dev/null || true
	@docker secret rm webhook_secret 2>/dev/null || true
	@docker secret rm cf_dns_api_token 2>/dev/null || true
	@$(MAKE) secrets
	@echo "⚠ Redeploy services to pick up new secrets"

secrets-list: ## List all secrets
	@docker secret ls

traefik: network ## Deploy traefik stack
	@docker stack deploy -c infrastructure/traefik/docker-compose.yml traefik
	@echo "✓ traefik deployed"

doco-cd: network secrets ## Deploy doco-cd stack
	@docker stack deploy -c infrastructure/doco-cd/docker-compose.yml doco-cd
	@echo "✓ doco-cd deployed"

prometheus: network ## Deploy prometheus stack
	@docker stack deploy -c infrastructure/prometheus/docker-compose.yml prometheus
	@echo "✓ prometheus deployed"

# =============================================================================
# OPERATIONS
# =============================================================================
status: ## Show stacks and services
	@echo "=== Stacks ==="
	@docker stack ls
	@echo ""
	@echo "=== Services ==="
	@docker service ls --format "table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}"

ps: ## Show service tasks
	@docker service ps $$(docker service ls -q) --format "table {{.Name}}\t{{.CurrentState}}\t{{.Error}}" 2>/dev/null | head -30

logs: ## Tail doco-cd logs
	@docker service logs -f --tail 100 doco-cd_doco-cd

logs-traefik: ## Tail traefik logs
	@docker service logs -f --tail 100 traefik_traefik

deploy: ## Deploy specific app (APP=apps/myapp)
	@test -n "$(APP)" || (echo "Usage: make deploy APP=apps/myapp" && exit 1)
	@docker stack deploy -c $(APP)/docker-compose.yml $$(basename $(APP))
	@echo "✓ $(APP) deployed"

down: ## Remove specific stack (APP=apps/myapp)
	@test -n "$(APP)" || (echo "Usage: make down APP=apps/myapp" && exit 1)
	@docker stack rm $$(basename $(APP))
	@echo "✓ $(APP) removed"

scale: ## Scale service (SVC=myapp_web REPLICAS=3)
	@test -n "$(SVC)" || (echo "Usage: make scale SVC=myapp_web REPLICAS=3" && exit 1)
	@docker service scale $(SVC)=$(REPLICAS)

restart: ## Force restart service (SVC=myapp_web)
	@test -n "$(SVC)" || (echo "Usage: make restart SVC=myapp_web" && exit 1)
	@docker service update --force $(SVC)

pull: ## Pull latest images
	@for f in $$(find . -name 'docker-compose.yml' -not -path './.claude/*'); do \
		echo "Pulling: $$f"; \
		docker compose -f $$f pull 2>/dev/null || true; \
	done

up-all: ## Deploy all stacks
	@$(MAKE) traefik
	@$(MAKE) doco-cd
	@for d in apps/*/; do \
		name=$$(basename $$d); \
		echo "Deploying: $$name"; \
		docker stack deploy -c $$d/docker-compose.yml $$name; \
	done

down-all: ## Remove all stacks
	@for stack in $$(docker stack ls --format '{{.Name}}'); do \
		echo "Removing: $$stack"; \
		docker stack rm $$stack; \
	done

clean: down-all ## Remove all stacks and prune
	@sleep 5
	@docker system prune -f
	@docker volume prune -f
	@echo "✓ cleaned"

# =============================================================================
# MONITORING & DEBUG
# =============================================================================
health: ## Check service health
	@echo "=== doco-cd ==="
	@curl -sf http://localhost:8080/v1/health 2>/dev/null && echo "" || echo "not responding"
	@echo "=== traefik ==="
	@curl -sf http://localhost:8080/ping 2>/dev/null && echo "" || echo "not responding"

services: ## List services with details
	@docker service ls

nodes: ## List swarm nodes
	@docker node ls

inspect: ## Inspect service (SVC=myapp_web)
	@test -n "$(SVC)" || (echo "Usage: make inspect SVC=myapp_web" && exit 1)
	@docker service inspect $(SVC) --pretty

# =============================================================================
# SECRETS ENCRYPTION (SOPS)
# =============================================================================
sops-keygen: ## Generate age key for SOPS
	@mkdir -p secrets
	@age-keygen -o secrets/sops_age_key.txt 2>&1 | tee secrets/sops_age_key.pub
	@echo "✓ age key generated in secrets/"
	@echo "Add public key to .sops.yaml"

sops-encrypt: ## Encrypt file (FILE=secrets/app.env)
	@test -n "$(FILE)" || (echo "Usage: make sops-encrypt FILE=secrets/app.env" && exit 1)
	@sops encrypt -i $(FILE)
	@echo "✓ $(FILE) encrypted"

sops-decrypt: ## Decrypt file (FILE=secrets/app.env)
	@test -n "$(FILE)" || (echo "Usage: make sops-decrypt FILE=secrets/app.env" && exit 1)
	@sops decrypt $(FILE)

# =============================================================================
# CLEANUP
# =============================================================================
leave: ## Leave swarm (DESTRUCTIVE!)
	@echo "WARNING: This will remove all services and leave swarm"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ]
	@docker swarm leave --force
