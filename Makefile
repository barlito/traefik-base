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
	@echo "  make wireguard-up    - Start WireGuard VPN (standalone container)"
	@echo "  make wireguard-down  - Stop WireGuard VPN"
	@echo "  make wireguard-logs  - Follow WireGuard logs"
	@echo "  make fail2ban-build  - Build the custom fail2ban image locally"
	@echo "  make fail2ban-up     - Pull & start fail2ban (host-level banning)"
	@echo "  make fail2ban-down   - Stop fail2ban"
	@echo "  make fail2ban-logs   - Follow fail2ban logs"
	@echo "  make fail2ban-status - Show fail2ban jails and banned IPs"
	@echo "  make fail2ban-test   - Validate the Traefik filter against the real log"
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
		sed "s|\$$AUTHELIA_USER_PASSWORD_HASH|$$AUTHELIA_USER_PASSWORD_HASH|" authelia/users.yml > authelia/users.local.yml && \
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
		sed "s|\$$AUTHELIA_USER_PASSWORD_HASH|$$AUTHELIA_USER_PASSWORD_HASH|" authelia/users.yml > authelia/users.local.yml && \
		docker stack deploy -c docker-compose.yml -c docker-compose.local.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://traefik.local.barlito.fr"
	@echo "🔐 Authelia: https://auth.local.barlito.fr"
	@echo "✅ HTTP/3 enabled on port 443/UDP"
endif

.PHONY: deploy-prod
deploy-prod:
	@echo "🚀 Deploying Traefik (production)..."
	@export CONFIG_VERSION=$$(cat traefik.prod.yml traefik-dynamic.prod.yml authelia/configuration.prod.yml authelia/users.yml | sha1sum | cut -c1-10) && \
		docker stack deploy -c docker-compose.yml -c docker-compose.prod.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://$$DASHBOARD_HOST"
	@echo "🔐 Authelia: https://auth.barlito.fr"

.PHONY: undeploy
undeploy:
	@echo "🗑️  Removing Traefik stack..."
	@docker stack rm $(stack_name) || true
	@echo "✅ Stack removed (network may remain if used by other services)!"

.PHONY: wireguard-up
wireguard-up:
	@echo "🔐 Starting WireGuard VPN..."
	@if [ -f .env.local ]; then \
		set -a && . ./.env.local && set +a && \
		docker compose -f docker-compose.wireguard.yml up -d; \
	else \
		docker compose -f docker-compose.wireguard.yml up -d; \
	fi
	@echo "✅ WireGuard running!"
	@echo "🌐 Web UI: https://vpn.local.barlito.fr (local) or https://vpn.barlito.fr (prod)"
	@echo "📱 Add clients from the web UI"

.PHONY: wireguard-down
wireguard-down:
	@echo "🗑️  Stopping WireGuard VPN..."
	@docker compose -f docker-compose.wireguard.yml down
	@echo "✅ WireGuard stopped!"

.PHONY: wireguard-logs
wireguard-logs:
	@docker compose -f docker-compose.wireguard.yml logs -f

.PHONY: fail2ban-build
fail2ban-build:
	@echo "🛠️  Building fail2ban image..."
	@docker build -t ghcr.io/barlito/traefik-base-fail2ban:latest ./fail2ban
	@echo "✅ Built ghcr.io/barlito/traefik-base-fail2ban:latest"

.PHONY: fail2ban-up
fail2ban-up:
	@echo "🛡️  Starting fail2ban..."
	@if [ -f .env.local ]; then \
		set -a && . ./.env.local && set +a && \
		docker compose -f docker-compose.fail2ban.yml pull && \
		docker compose -f docker-compose.fail2ban.yml up -d; \
	else \
		docker compose -f docker-compose.fail2ban.yml pull && \
		docker compose -f docker-compose.fail2ban.yml up -d; \
	fi
	@echo "✅ fail2ban running! (jails: sshd, traefik-badbots)"

.PHONY: fail2ban-down
fail2ban-down:
	@echo "🗑️  Stopping fail2ban..."
	@docker compose -f docker-compose.fail2ban.yml down
	@echo "✅ fail2ban stopped!"

.PHONY: fail2ban-logs
fail2ban-logs:
	@docker compose -f docker-compose.fail2ban.yml logs -f

.PHONY: fail2ban-status
fail2ban-status:
	@docker exec fail2ban fail2ban-client status || true
	@echo "--- traefik-badbots ---" && docker exec fail2ban fail2ban-client status traefik-badbots || true
	@echo "--- sshd ---" && docker exec fail2ban fail2ban-client status sshd || true

# Dry-run the Traefik filter against the real access log: reports how many lines
# matched and which IPs would be banned, without touching the firewall.
.PHONY: fail2ban-test
fail2ban-test:
	@docker exec fail2ban fail2ban-regex /var/log/traefik/access.log /data/filter.d/traefik-badbots.conf

.PHONY: logs
logs:
	@docker service logs -f $(stack_name)_traefik
