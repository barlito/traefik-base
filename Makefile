stack_name=traefik

# Default environment
ENV ?= local

.PHONY: help
help:
	@echo "Traefik Stack Management"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy          - Deploy with local config (default)"
	@echo "  make deploy ENV=prod - Deploy with production config"
	@echo "  make undeploy        - Remove the stack"
	@echo "  make logs            - Follow traefik logs"
	@echo "  make restart         - Restart the stack"
	@echo ""

.PHONY: deploy
deploy:
	@echo "Deploying traefik stack with $(ENV) configuration..."
	@if [ "$(ENV)" = "prod" ]; then \
		echo "Using production configuration"; \
		set -a && . ./.env.production && set +a && docker stack deploy -c docker-compose.yml $(stack_name); \
	else \
		echo "Using local configuration"; \
		set -a && . ./.env.local && set +a && docker stack deploy -c docker-compose.yml $(stack_name); \
	fi
	@echo "Dashboard URL: https://$(shell grep DASHBOARD_HOST .env.$(ENV) 2>/dev/null | cut -d'=' -f2 || echo 'traefik.local.barlito.fr')"

.PHONY: undeploy
undeploy:
	docker stack rm $(stack_name)

.PHONY: logs
logs:
	docker service logs -f $(stack_name)_traefik

.PHONY: restart
restart: undeploy
	@echo "Waiting for stack to be removed..."
	@sleep 5
	@$(MAKE) deploy ENV=$(ENV)
