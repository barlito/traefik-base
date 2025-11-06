# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a production-ready Traefik 3.0 reverse proxy setup using Docker Swarm with environment-specific configurations (local vs production).

**Key architectural decisions:**

1. **Docker Compose override pattern**: Base config (`docker-compose.yml`) + environment-specific overrides (`docker-compose.{local,wsl,prod}.yml`)
2. **Dual static configs**: `traefik.local.yml` (DEBUG, mkcert certs) vs `traefik.prod.yml` (INFO, Let's Encrypt)
3. **HTTP/3 on alternative port**: Port 444/UDP for HTTP/3 instead of 443/UDP due to Docker Swarm limitation (cannot publish TCP+UDP on same port)
4. **Production uses Docker configs**: Config files transferred via Docker API, no rsync needed
5. **Local uses bind mounts**: Direct file mounting for easy development iteration

## Common Commands

### Deployment
```bash
# Auto-detects WSL vs Linux and deploys accordingly
make deploy-local

# Production deployment (manual or via GitHub Actions)
make deploy-prod

# Remove stack
make undeploy
```

### Viewing Logs
```bash
# All logs (stdout/stderr)
make logs
# or
docker service logs -f traefik_traefik
```

### Testing and Verification
```bash
# Check service status
docker service ps traefik_traefik

# Inspect published ports
docker service inspect traefik_traefik --format '{{json .Endpoint.Ports}}' | python3 -m json.tool
```

### Secret Generation
```bash
# Interactive script for production secrets
./scripts/generate-secrets.sh
```

## Git Workflow

- `master` branch: stable releases
- Feature branches: named descriptively
- Current work branches should be merged via PR after testing manually by the user
