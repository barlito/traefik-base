# Traefik Base Configuration

Production-ready Traefik 3.7 setup with Docker Compose overrides for local/production.

## Features

- 🚀 HTTP/3 support on port 444/UDP (host-mode publishing, all environments)
- 🔒 Automatic HTTP → HTTPS redirect
- 🛡️ Security headers (HSTS, X-Frame-Options, CSP, etc.)
- 🔐 Secure dashboard with Authelia (forwardAuth in production)
- 📜 Let's Encrypt automatic certificates
- 📊 Structured JSON logs (app log on stdout, ready for Loki/Fluentd; prod access log in a host file for fail2ban)
- 🔌 **Docker socket proxy**: Traefik reaches the Swarm API through a read-only `dockerproxy`, the socket is never mounted into Traefik
- 🚫 **fail2ban** at host level (bans on the Traefik access log)
- 📦 **Docker Configs for prod** (no file sync needed!)
- 🔧 **Bind mounts for local** (easy config editing)
- 🔒 **WireGuard VPN** via wg-easy (web UI, QR codes, split tunnel)
- 🔥 **Default-deny firewall** for host AND containers (INPUT + DOCKER-USER)

## Quick Start

### Local Development

```bash
# 1. Copy local configuration and fill in the AUTHELIA_* values
#    (generation commands are in the file's comments)
cp .env.example .env.local

# 2. Deploy (same on Linux and WSL)
make deploy-local
```

Dashboard: https://traefik.local.barlito.fr (no authentication required)

A self-signed wildcard certificate for `*.local.barlito.fr` is committed in `certs/`
(local only — see [certs/README.md](certs/README.md) to trust or regenerate it).

Linux and WSL use the same override (`docker-compose.local.yml`): ports are published
in host mode from the base `docker-compose.yml` in every environment (HTTP/3 on 444/UDP).

**Local uses bind mounts** - you can edit config files directly and they're reflected in the container.

### Production

```bash
# Deploy to production (via GitHub Actions or manually)
make deploy-prod
```

Dashboard: https://traefik.barlito.fr (Authelia authentication required)
Authelia: https://auth.barlito.fr

**Production uses Docker configs** - configs are transferred via Docker API, no file sync needed!

## Available Commands

```bash
make help           # Show help message
make deploy-local   # Deploy local (bind mounts, self-signed cert)
make deploy-prod    # Deploy production (Docker configs, Let's Encrypt)
make undeploy       # Remove the stack
make logs           # Follow Traefik service logs (via docker service logs)

# Standalone containers (outside Swarm), see the sections below
make wireguard-up | wireguard-down | wireguard-logs
make fail2ban-build | fail2ban-up | fail2ban-down | fail2ban-logs | fail2ban-status | fail2ban-test
make firewall-build | firewall-up | firewall-down | firewall-flush | firewall-status | firewall-logs
```

## Network Configuration

### Ports

- **80/TCP** - HTTP (redirects to HTTPS)
- **443/TCP** - HTTPS (HTTP/2)
- **444/UDP** - HTTP/3 (QUIC)

All ports are published in **host mode** (not the Swarm ingress mesh).
The dashboard has no dedicated port: it is served by the `dashboard` router
on 443 (`api@internal`); 8080 (insecure API) is disabled and not published.

### Why host mode

The ingress routing mesh SNATs every incoming connection to the mesh IP
(`10.0.0.2`), which hides the real client and breaks per-IP defenses (fail2ban,
rate limiting, geo-blocking). Host mode binds ports directly on the node running
Traefik, preserving the source IP.

### Why HTTP/3 uses port 444, not 443

Docker Swarm deduplicates a service's published ports by number and keeps only
**one** entry when the same port appears for both TCP and UDP — and this happens
**even in host mode** ([moby/moby#43429](https://github.com/moby/moby/issues/43429)).
Publishing `443/tcp` + `443/udp` leaves only one of them (killing either HTTPS or
HTTP/3). So TCP and UDP must use different published ports: HTTPS on 443/TCP,
HTTP/3 on 444/UDP, announced to browsers via Traefik's `advertisedPort: 444`.

**HTTP/3 flow:** clients connect via HTTPS on 443/TCP, Traefik advertises
`alt-svc: h3=":444"`, browsers upgrade to HTTP/3 on 444/UDP, with automatic
fallback to HTTP/2.

**Trade-off:** no routing-mesh load balancing — ports bind only on the node
running Traefik. Fine here: Traefik is pinned to a single manager replica.

The Makefile automatically detects your environment and deploys the correct configuration.

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ENV` | Environment (local/production) | `local` |
| `DASHBOARD_HOST` | Dashboard domain | `traefik.barlito.fr` |
| `AUTHELIA_JWT_SECRET` | Authelia JWT signing secret | `openssl rand -base64 32` |
| `AUTHELIA_SESSION_SECRET` | Authelia session encryption | `openssl rand -base64 32` |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | Authelia storage encryption | `openssl rand -base64 32` |
| `ACME_EMAIL` | Let's Encrypt email (prod only) | `admin@example.com` |

### Configuration Files

**Docker Compose**:
- `docker-compose.yml` - Base configuration (common to all environments)
- `docker-compose.local.yml` - Local override, Linux and WSL (bind mounts)
- `docker-compose.prod.yml` - Production override (Docker configs, access log bind-mounted for fail2ban)
- `docker-compose.wireguard.yml` / `docker-compose.fail2ban.yml` / `docker-compose.firewall.yml` - Standalone containers (outside Swarm)

**Traefik Config**:
- `traefik.local.yml` - Local static configuration (no Let's Encrypt, DEBUG logs)
- `traefik.prod.yml` - Production static configuration (Let's Encrypt, INFO logs)
- `traefik-dynamic.local.yml` - Local dynamic config (no auth)
- `traefik-dynamic.prod.yml` - Production dynamic config (with auth)
- `authelia/` - Authelia configuration (local/prod) and file-based users

### Certificates

**Local**: Self-signed wildcard certificate committed in `certs/` (see [certs/README.md](certs/README.md); [mkcert](https://github.com/FiloSottile/mkcert) is an alternative for a browser-trusted one)

**Production**: Automatic Let's Encrypt via HTTP challenge

## WireGuard VPN

WireGuard VPN via [wg-easy](https://github.com/wg-easy/wg-easy) — web UI for client management and QR codes.

> WireGuard runs as a standalone container (`docker compose`) because Docker Swarm does not support `cap_add`.

### Setup

```bash
# 1. Set WG_HOST in .env.local (server public IP)
# WG_HOST=<server public IP or domain>

# 2. Start WireGuard
make wireguard-up

# 3. Open the web UI to create clients
# https://vpn.barlito.fr (prod) / https://vpn.local.barlito.fr (local)
```

### Commands

```bash
make wireguard-up     # Start WireGuard
make wireguard-down   # Stop WireGuard
make wireguard-logs   # Follow logs
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WG_HOST` | Server public IP or domain (required) | - |
| `WG_PORT` | WireGuard UDP port | `51820` |
| `WG_DEFAULT_DNS` | DNS servers for clients | `1.1.1.1, 8.8.8.8` |
| `WG_ALLOWED_IPS` | IPs routed through VPN | `0.0.0.0/0` (full tunnel) |
| `WG_PERSISTENT_KEEPALIVE` | Keepalive interval (seconds) | `25` |

### Split Tunnel

By default, all client traffic goes through the VPN (`0.0.0.0/0`). To only route traffic to the server (split tunnel), edit `AllowedIPs` in the client config:

```ini
AllowedIPs = 10.8.0.0/24, <SERVER_PUBLIC_IP>/32
```

## Firewall (host + containers)

Default-deny firewall covering both the host (`INPUT`: SSH only) and the
published container ports (`DOCKER-USER`: Traefik 80/443/444 + WireGuard
51820 only). Any other published port — a debug database, a forgotten admin
UI — is unreachable from the internet. Host firewalls like UFW can't do
this: Docker's DNAT bypasses `INPUT` entirely.

> Like WireGuard/fail2ban, it runs as a standalone container (host netns +
> `NET_ADMIN`) with the ruleset baked into a GHCR image. Fail-open design:
> established connections always pass, so it can never cut the SSH session
> that would fix it.

```bash
make firewall-up       # pull + start
make firewall-status   # chains + packet counters
make firewall-flush    # remove the rules entirely
```

See [docs/FIREWALL.md](docs/FIREWALL.md) for the DOCKER-USER mechanics,
policy details and how to open a port for a future game server, and
[docs/SERVER_OPS.md](docs/SERVER_OPS.md) for the on-server cheatsheet
(verify the firewall, list banned IPs — raw commands, no Makefile).

## Security

Production deployment includes:

- ✅ Dashboard protected with Authelia (forwardAuth + TOTP/WebAuthn support)
- ✅ Automatic HTTP → HTTPS redirect
- ✅ Security headers (HSTS with preload, X-Frame-Options, etc.)
- ✅ INFO log level (no verbose debug logs)
- ✅ Let's Encrypt with automatic renewal
- ✅ TLS 1.2+ only with secure cipher suites
- ✅ JSON access logs (4xx/5xx errors only) written to `/var/log/traefik/access.log` on the host, tailed by fail2ban
- ✅ Docker socket exposed to Traefik only through a read-only proxy (`dockerproxy`, writes refused)
- ✅ Host-level fail2ban and default-deny firewall (see [docs/FAIL2BAN.md](docs/FAIL2BAN.md) and [docs/FIREWALL.md](docs/FIREWALL.md))

For detailed security headers explanation, see [docs/SECURITY_HEADERS.md](docs/SECURITY_HEADERS.md)

## Automated Deployment (GitHub Actions)

Deploy automatically from GitHub using secrets management.

See [docs/GITHUB_ACTIONS.md](docs/GITHUB_ACTIONS.md) for setup instructions.

**Benefits**:
- No `.env.production` file in repository
- Secrets managed by GitHub
- Manual deployment trigger (workflow_dispatch)
- Deployment traceability

## Monitoring

### Logs

The Traefik application log (DEBUG locally, INFO in production) goes to **stdout** for
Docker-native logging. The **access log** differs per environment: disabled locally,
and in production written as JSON (4xx/5xx only) to `/var/log/traefik/access.log` on the
host (bind mount) so the standalone fail2ban container can tail it, instead of stdout.

```bash
# View all logs (local or prod)
make logs

# Or directly with docker
docker service logs -f traefik_traefik
```

**For centralized logging**, no configuration is needed: the [observability-stack](https://github.com/barlito/observability-stack) runs an Alloy agent on each node that discovers every container through the Docker socket and ships stdout/stderr to Loki automatically. Logs are queryable in Grafana with labels `container`, `service` and `stack` (e.g. `{service="traefik_traefik"}`).

### Metrics

In production, Prometheus metrics are already enabled in `traefik.prod.yml` on an
internal-only `metrics` entrypoint (`:8082`, not published to the host), meant to be
scraped from inside the `traefik_proxy` overlay network.

## Troubleshooting

### Dashboard not accessible

Check DNS configuration:
```bash
# Local
echo "127.0.0.1 traefik.local.barlito.fr" | sudo tee -a /etc/hosts

# Production
dig traefik.barlito.fr
```

### Certificate error locally

The local certificate is self-signed: the browser warns until you trust it, and it
expires on 2029-02-12. See [certs/README.md](certs/README.md) to trust or regenerate it.

### Let's Encrypt rate limit

Use staging environment:
```yaml
certificatesResolvers:
  letsencrypt:
    acme:
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory
```

## Project Structure

```
traefik-base/
├── .env.example                 # Environment template
├── .github/workflows/           # CI: deploy (stack, VPN, fail2ban, firewall) + image builds
│   ├── deploy.yml               # Deploy the Traefik/Authelia stack
│   ├── deploy-vpn.yml           # Deploy WireGuard
│   ├── deploy-fail2ban.yml      # Deploy fail2ban
│   ├── deploy-firewall.yml      # Deploy the firewall
│   ├── build-fail2ban.yml       # Build & push the fail2ban image to GHCR
│   └── build-firewall.yml       # Build & push the firewall image to GHCR
├── docker-compose.yml           # Base configuration (Traefik, dockerproxy, Authelia)
├── docker-compose.local.yml     # Local override, Linux and WSL (bind mounts)
├── docker-compose.prod.yml      # Production override (Docker configs)
├── docker-compose.wireguard.yml # WireGuard VPN (standalone, docker compose)
├── docker-compose.fail2ban.yml  # fail2ban (standalone, host network)
├── docker-compose.firewall.yml  # Firewall (standalone, host network)
├── traefik.local.yml            # Local static config (DEBUG, no Let's Encrypt)
├── traefik.prod.yml             # Production static config (INFO, Let's Encrypt)
├── traefik-dynamic.local.yml    # Local dynamic config (no auth)
├── traefik-dynamic.prod.yml     # Production dynamic config (with auth)
├── authelia/                    # Authelia configuration
│   ├── configuration.local.yml  # Local config (debug, local domain)
│   ├── configuration.prod.yml   # Production config (info, prod domain)
│   └── users.yml                # User database (password hash injected by CI)
├── fail2ban/                    # fail2ban image sources (config baked into the image)
├── firewall/                    # Firewall image sources (ruleset baked into the image)
├── Makefile                     # Deployment commands
├── certs/                       # Local self-signed certificate
├── docs/                        # Documentation
│   ├── SECURITY_HEADERS.md      # Security headers explained
│   ├── GITHUB_ACTIONS.md        # CI/CD setup guide
│   ├── FAIL2BAN.md              # fail2ban setup and tuning
│   ├── FIREWALL.md              # Firewall design and how to open a port
│   └── SERVER_OPS.md            # On-server cheatsheet
└── scripts/
    └── generate-secrets.sh      # Secret generation helper
```

## License

MIT
