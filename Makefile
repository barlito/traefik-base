stack_name=traefik

.PHONY: help
help:
	@echo "Traefik Stack Management"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy-local    - Deploy local (bind mounts, mkcert certs)"
	@echo "  make deploy-prod     - Deploy production (Docker configs, Let's Encrypt)"
	@echo "  make undeploy        - Remove the stack"
	@echo "  make logs            - Follow traefik logs"
	@echo "  make logs-local      - View local logs (from ./logs/)"
	@echo "  make logs-prod       - Export prod logs (from Docker volume)"
	@echo ""

.PHONY: deploy-local
deploy-local:
	@echo "📦 Deploying Traefik (local)..."
	@if [ ! -f .env.local ]; then \
		echo "⚠️  .env.local not found, creating from example..."; \
		cp .env.example .env.local; \
	fi
	@set -a && . ./.env.local && set +a && \
		docker stack deploy -c docker-compose.yml -c docker-compose.local.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://traefik.local.barlito.fr"

.PHONY: deploy-prod
deploy-prod:
	@echo "🚀 Deploying Traefik (production)..."
	@docker stack deploy -c docker-compose.yml -c docker-compose.prod.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://$$DASHBOARD_HOST"

.PHONY: undeploy
undeploy:
	@echo "🗑️  Removing Traefik stack..."
	@docker stack rm $(stack_name)
	@echo "✅ Stack removed!"

.PHONY: logs
logs:
	@docker service logs -f $(stack_name)_traefik

.PHONY: logs-local
logs-local:
	@tail -f logs/access.log

.PHONY: logs-prod
logs-prod:
	@echo "📥 Exporting production logs..."
	@docker run --rm -v $(stack_name)_traefik-logs:/logs -v $$(pwd):/backup alpine \
		tar czf /backup/logs-export-$$(date +%Y%m%d-%H%M%S).tar.gz -C /logs .
	@echo "✅ Logs exported to logs-export-*.tar.gz"
