.PHONY: help bootstrap swarm-init network traefik doco-cd status logs deploy down pull clean ps

SHELL := /bin/bash
.DEFAULT_GOAL := help

-include .env
export

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

# Bootstrap
bootstrap: swarm-init network traefik doco-cd ## Bootstrap full stack (swarm mode)

swarm-init: ## Initialize Docker Swarm
	@docker info --format '{{.Swarm.LocalNodeState}}' | grep -q active || docker swarm init
	@echo "✓ swarm initialized"

network: ## Create traefik overlay network
	@docker network inspect traefik >/dev/null 2>&1 || docker network create --driver overlay --attachable traefik
	@echo "✓ traefik network ready"

traefik: network ## Deploy traefik stack
	@docker stack deploy -c infrastructure/traefik/docker-compose.yml traefik
	@echo "✓ traefik deployed"

doco-cd: network ## Deploy doco-cd stack
	@docker stack deploy -c infrastructure/doco-cd/docker-compose.yml doco-cd
	@echo "✓ doco-cd deployed"

# Operations
status: ## Show running services
	@docker stack ls
	@echo ""
	@docker service ls

ps: ## Show service tasks
	@docker stack ps --no-trunc $$(docker stack ls --format '{{.Name}}') 2>/dev/null || echo "No stacks running"

logs: ## Tail doco-cd logs
	@docker service logs -f doco-cd_doco-cd

logs-traefik: ## Tail traefik logs
	@docker service logs -f traefik_traefik

deploy: ## Deploy specific app as stack (APP=apps/myapp)
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

pull: ## Pull latest images for all apps
	@for f in $$(find . -name 'docker-compose.yml' -not -path './.claude/*'); do \
		echo "Pulling: $$f"; \
		docker compose -f $$f pull; \
	done

up-all: ## Deploy all stacks
	@for d in infrastructure/traefik infrastructure/doco-cd apps/*/; do \
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
	@echo "✓ cleaned"

# Debug
health: ## Check doco-cd health
	@curl -s http://localhost:8080/v1/health | jq . || echo "doco-cd not responding"

services: ## List all services with details
	@docker service ls --format "table {{.Name}}\t{{.Mode}}\t{{.Replicas}}\t{{.Image}}"

nodes: ## List swarm nodes
	@docker node ls

leave: ## Leave swarm (destructive!)
	@docker swarm leave --force
