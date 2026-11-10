# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready Traefik 3.7 reverse proxy setup using Docker Swarm with environment-specific configurations (local vs production).

**Key architectural decisions:**

1. **Docker Compose override pattern**: Base config (`docker-compose.yml`) + environment-specific overrides (`docker-compose.{local,prod}.yml`). Linux and WSL share the same local override.
2. **Dual static configs**: `traefik.local.yml` (DEBUG, self-signed cert committed in `certs/`, no access log) vs `traefik.prod.yml` (INFO, Let's Encrypt). Application logs go to stdout; in prod the JSON access log (4xx/5xx only) is written to `/var/log/traefik/access.log` on the host (bind mount) for fail2ban.
3. **Host-mode publishing everywhere**: ports are published in host mode from the base compose (no ingress mesh SNAT, real client IP preserved). HTTP/3 is on 444/UDP in every environment, not 443/UDP, because Docker Swarm cannot publish TCP+UDP on the same port number (even in host mode).
4. **docker-socket-proxy**: Traefik's Swarm provider talks to the read-only `dockerproxy` service over `tcp://dockerproxy:2375`; the Docker socket is not mounted into Traefik.
5. **Production uses Docker configs**: Config files transferred via Docker API, no rsync needed (names suffixed with `CONFIG_VERSION`, a hash computed by `make deploy-prod`)
6. **Local uses bind mounts**: Direct file mounting for easy development iteration
7. **Authelia for auth**: Lightweight forwardAuth via Traefik to protect services without native auth (dashboard, tools). File-based users (`authelia/users.yml`), password hash injected from GitHub secret at deploy time. Supports TOTP/WebAuthn as second factor.
8. **Standalone (non-Swarm) containers**: WireGuard (wg-easy), fail2ban and the default-deny firewall need `cap_add`/host networking, which `docker stack deploy` does not support, so they run with `docker compose` (`docker-compose.{wireguard,fail2ban,firewall}.yml`). fail2ban and firewall configs are baked into images built by GitHub Actions and pushed to GHCR (`fail2ban/`, `firewall/`).

## Common Commands

Run `make help` for the full list.

```bash
# Traefik stack
make deploy-local        # local (Linux and WSL)
make deploy-prod         # production (manual or via GitHub Actions)
make undeploy            # remove the stack
make logs                # follow Traefik service logs

# WireGuard
make wireguard-up | wireguard-down | wireguard-logs

# fail2ban (host-level banning)
make fail2ban-build | fail2ban-up | fail2ban-down | fail2ban-logs | fail2ban-status | fail2ban-test

# Firewall (host INPUT + DOCKER-USER)
make firewall-build | firewall-up | firewall-down | firewall-flush | firewall-status | firewall-logs
```

### Testing and Verification
```bash
docker service ps traefik_traefik
docker service inspect traefik_traefik --format '{{json .Endpoint.Ports}}' | python3 -m json.tool
```

### Secret Generation
```bash
./scripts/generate-secrets.sh   # interactive, production secrets
```

Docs: `docs/` (GITHUB_ACTIONS, SECURITY_HEADERS, FAIL2BAN, FIREWALL, SERVER_OPS).

## Git Workflow

- `master` branch: stable releases
- Feature branches: named descriptively
- Current work branches should be merged via PR after testing manually by the user
