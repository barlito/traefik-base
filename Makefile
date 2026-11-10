stack_name=traefik

.PHONY: help
help:
	@echo "Traefik Stack Management"
	@echo ""
	@echo "Usage:"
	@echo "  make deploy-local    - Deploy local (bind mounts, HTTP/3 on 444/UDP)"
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
	@echo "  make firewall-build  - Build the custom firewall image locally"
	@echo "  make firewall-up     - Pull & start the firewall (host + containers)"
	@echo "  make firewall-down   - Stop the firewall container (rules stay)"
	@echo "  make firewall-flush  - Remove ALL firewall rules from the host"
	@echo "  make firewall-status - Show the firewall chains and counters"
	@echo "  make firewall-logs   - Follow firewall logs"
	@echo ""

.PHONY: deploy-local
deploy-local:
	@echo "📦 Deploying Traefik (local, HTTP/3 on 444/UDP)..."
	@if [ ! -f .env.local ]; then \
		echo "⚠️  .env.local not found, creating from .env.example..."; \
		cp .env.example .env.local; \
		echo "❌ .env.local created: fill in the empty AUTHELIA_* values (generation commands are in the file's comments), then re-run 'make deploy-local'."; \
		exit 1; \
	fi
	@set -a && . ./.env.local && set +a && \
		for v in AUTHELIA_JWT_SECRET AUTHELIA_SESSION_SECRET AUTHELIA_STORAGE_ENCRYPTION_KEY AUTHELIA_USER_PASSWORD_HASH; do \
			eval "val=\$$$$v"; \
			if [ -z "$$val" ]; then \
				echo "❌ $$v is empty in .env.local: fill it in (generation commands are in the file's comments), then re-run 'make deploy-local'."; \
				exit 1; \
			fi; \
		done && \
		sed "s|\$$AUTHELIA_USER_PASSWORD_HASH|$$AUTHELIA_USER_PASSWORD_HASH|" authelia/users.yml > authelia/users.local.yml && \
		docker stack deploy -c docker-compose.yml -c docker-compose.local.yml $(stack_name)
	@echo "✅ Deployed!"
	@echo "📊 Dashboard: https://traefik.local.barlito.fr"
	@echo "🔐 Authelia: https://auth.local.barlito.fr"
	@echo "✅ HTTP/3 enabled on port 444/UDP"

.PHONY: deploy-prod
deploy-prod:
	@if grep -qF '$$ACME_EMAIL' traefik.prod.yml; then \
		echo "❌ traefik.prod.yml still contains the \$$ACME_EMAIL placeholder: render it first (the deploy workflow does it with sed)."; exit 1; \
	fi
	@if grep -qF '$$AUTHELIA_USER_PASSWORD_HASH' authelia/users.yml; then \
		echo "❌ authelia/users.yml still contains the \$$AUTHELIA_USER_PASSWORD_HASH placeholder: render it first (the deploy workflow does it with sed)."; exit 1; \
	fi
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

.PHONY: firewall-build
firewall-build:
	@echo "🛠️  Building firewall image..."
	@docker build -t ghcr.io/barlito/traefik-base-firewall:latest ./firewall
	@echo "✅ Built ghcr.io/barlito/traefik-base-firewall:latest"

.PHONY: firewall-up
firewall-up:
	@echo "🔥 Starting firewall (host INPUT + DOCKER-USER filtering)..."
	@docker compose -f docker-compose.firewall.yml pull
	@docker compose -f docker-compose.firewall.yml up -d
	@echo "✅ Firewall running! (make firewall-status to inspect)"

.PHONY: firewall-down
firewall-down:
	@echo "🗑️  Stopping firewall container (rules STAY in place)..."
	@docker compose -f docker-compose.firewall.yml down
	@echo "ℹ️  To remove the rules too: make firewall-flush"

.PHONY: firewall-flush
firewall-flush:
	@echo "🧹 Removing firewall rules from the host..."
	@docker compose -f docker-compose.firewall.yml down 2>/dev/null || true
	@docker run --rm --network host --cap-add NET_ADMIN --cap-add NET_RAW \
		-e FLUSH=1 ghcr.io/barlito/traefik-base-firewall:latest
	@echo "✅ Host back to Docker defaults (everything published is exposed!)"

.PHONY: firewall-status
firewall-status:
	@docker exec firewall sh -c ' \
		IPT=iptables-nft; iptables-nft -t nat -S DOCKER >/dev/null 2>&1 || IPT=iptables-legacy; \
		echo "--- INPUT (host) ---"; $$IPT -L BARLITO-FW-INPUT -v -n; \
		echo "--- DOCKER-USER (containers) ---"; $$IPT -L BARLITO-FW-DOCKER -v -n'

.PHONY: firewall-logs
firewall-logs:
	@docker compose -f docker-compose.firewall.yml logs -f

.PHONY: logs
logs:
	@docker service logs -f $(stack_name)_traefik
