stack_name=traefik

# Detect WSL environment
IS_WSL := $(shell grep -qi microsoft /proc/version 2>/dev/null && echo "true" || echo "false")

.PHONY: help
help:
	@echo "Traefik Stack Management"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy-local    - Deploy local (auto-detects WSL vs Linux)"
	@echo "  make deploy-prod     - Deploy production (Docker configs, Let's Encrypt)"
	@echo "  make undeploy        - Remove the stack"
	@echo "  make logs            - Follow traefik logs (via docker service logs)"
	@echo ""
ifeq ($(IS_WSL),true)
	@echo "🔍 WSL detected - will use docker-compose.wsl.yml (no HTTP/3)"
else
	@echo "🔍 Linux detected - will use docker-compose.local.yml (with HTTP/3)"
endif
	@echo ""

.PHONY: deploy-local
deploy-local:
ifeq ($(IS_WSL),true)
	@echo "📦 Deploying Traefik (local on WSL - no HTTP/3)..."
	@if [ ! -f .env.local ]; then \
		echo "⚠️  .env.local not found, creating from example..."; \
		cp .env.example .env.local; \
	fi
	@set -a && . ./.env.local && set +a && \
		docker stack deploy -c docker-compose.yml -c docker-compose.wsl.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://traefik.local.barlito.fr"
	@echo "🔐 Authelia: https://auth.local.barlito.fr"
	@echo "ℹ️  HTTP/3 disabled (WSL limitation)"
else
	@echo "📦 Deploying Traefik (local on Linux - with HTTP/3)..."
	@if [ ! -f .env.local ]; then \
		echo "⚠️  .env.local not found, creating from example..."; \
		cp .env.example .env.local; \
	fi
	@set -a && . ./.env.local && set +a && \
		docker stack deploy -c docker-compose.yml -c docker-compose.local.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://traefik.local.barlito.fr"
	@echo "🔐 Authelia: https://auth.local.barlito.fr"
	@echo "✅ HTTP/3 enabled on port 443/UDP"
endif

.PHONY: deploy-prod
deploy-prod:
	@echo "🚀 Deploying Traefik (production)..."
	@docker stack deploy -c docker-compose.yml -c docker-compose.prod.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://$$DASHBOARD_HOST"
	@echo "🔐 Authelia: https://auth.barlito.fr"

.PHONY: undeploy
undeploy:
	@echo "🗑️  Removing Traefik stack..."
	@docker stack rm $(stack_name) || true
	@echo "✅ Stack removed (network may remain if used by other services)!"

.PHONY: logs
logs:
	@docker service logs -f $(stack_name)_traefik
