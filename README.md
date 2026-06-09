# Traefik Base Configuration

Production-ready Traefik 3.0 setup with Docker Compose overrides for local/production.

## Features

- 🚀 HTTP/3 support on port 8443 (works everywhere: Linux, WSL, Production)
- 🔒 Automatic HTTP → HTTPS redirect
- 🛡️ Security headers (HSTS, X-Frame-Options, CSP, etc.)
- 🔐 Secure dashboard with Authelia (forwardAuth in production)
- 📜 Let's Encrypt automatic certificates
- 📊 Structured JSON logs to stdout (ready for Loki/Fluentd)
- 🐧 **Auto-detection**: WSL vs Linux (automatic in `make deploy-local`)
- 📦 **Docker Configs for prod** (no file sync needed!)
- 🔧 **Bind mounts for local** (easy config editing)
- 🔒 **WireGuard VPN** via wg-easy (web UI, QR codes, split tunnel)

## Quick Start

### Local Development

```bash
# 1. Copy local configuration
cp .env.example .env.local

# 2. Generate local certificates
mkdir -p certs
mkcert -cert-file certs/local-cert.pem -key-file certs/local-key.pem "*.local.barlito.fr"

# 3. Deploy (auto-detects WSL vs Linux)
make deploy-local
```

Dashboard: https://traefik.local.barlito.fr (no authentication required)

**Auto-detection**: The Makefile automatically detects if you're on WSL or Linux:
- **Linux**: Uses `docker-compose.local.yml` with HTTP/3 support (TCP+UDP on port 443)
- **WSL**: Uses `docker-compose.wsl.yml` without HTTP/3 (TCP only, due to WSL port limitations)

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
make deploy-local   # Deploy local (bind mounts, mkcert certs)
make deploy-prod    # Deploy production (Docker configs, Let's Encrypt)
make undeploy       # Remove the stack
make logs           # Follow Traefik service logs (via docker service logs)
```

## Network Configuration

### Ports

- **80/TCP** - HTTP (redirects to HTTPS)
- **443/TCP** - HTTPS (HTTP/2)
- **8443/UDP** - HTTP/3 (QUIC)
- **8080/TCP** - Dashboard

### HTTP/3 on Alternative Port

HTTP/3 runs on **port 8443/UDP** instead of 443/UDP to avoid Docker Swarm limitations with TCP+UDP on the same port.

**How it works:**
1. Clients connect via HTTPS on 443/TCP
2. Traefik sends `alt-svc: h3=":8443"` header
3. Browsers automatically upgrade to HTTP/3 on 8443/UDP for subsequent requests

**Benefits:**
- ✅ Works on all environments (Linux, WSL, Production)
- ✅ No port conflict between TCP and UDP
- ✅ Automatic HTTP/3 upgrade via standard `alt-svc` mechanism
- ✅ Fallback to HTTP/2 if HTTP/3 unavailable

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
- `docker-compose.local.yml` - Local override for Linux (bind mounts, HTTP/3)
- `docker-compose.wsl.yml` - Local override for WSL (bind mounts, no HTTP/3)
- `docker-compose.prod.yml` - Production override (Docker configs)

**Traefik Config**:
- `traefik.local.yml` - Local static configuration (no Let's Encrypt, DEBUG logs)
- `traefik.prod.yml` - Production static configuration (Let's Encrypt, INFO logs)
- `traefik-dynamic.local.yml` - Local dynamic config (no auth)
- `traefik-dynamic.prod.yml` - Production dynamic config (with auth)

### Certificates

**Local**: Real Let's Encrypt wildcard for `*.local.barlito.fr` via **DNS-01** (OVH), with [mkcert](https://github.com/FiloSottile/mkcert) self-signed as fallback.

DNS-01 validates ownership through a TXT record created via the OVH API, so it works even though `*.local.barlito.fr` resolves to `127.0.0.1` — the domain never needs to be publicly reachable. The cert resolver is declared at the `https` entrypoint level in `traefik.local.yml`: every local project gets the wildcard automatically, no TLS labels needed.

```bash
# 1. Create an OVH API token: https://eu.api.ovh.com/createToken
#    Rights: GET + POST + DELETE on /domain/zone/*
# 2. Fill OVH_* variables in .env.local (see .env.example)
# 3. Redeploy
make deploy-local
```

**FAQ — do I always need the OVH creds?**
- The ACME TXT record is *temporary* (created and deleted at each challenge), so the creds are needed at **first issuance and at every renewal** (~every 60 days, certs last 90). Keep them in `.env.local`.
- **Another of your machines**: copy the same `.env.local` (the token is not tied to a machine).
- **Someone else running this stack**: without your creds, Traefik logs ACME errors and serves the mkcert/self-signed fallback — everything works, just without trusted certs. Don't share the token (it grants write access to the DNS zone); they should use their own domain/creds.

**Production**: Automatic Let's Encrypt via HTTP challenge

## WireGuard VPN

WireGuard VPN via [wg-easy](https://github.com/wg-easy/wg-easy) — web UI for client management and QR codes.

> WireGuard runs as a standalone container (`docker compose`) because Docker Swarm does not support `cap_add`.

### Setup

```bash
# 1. Set WG_HOST in .env.local (server public IP)
# WG_HOST=51.68.154.52

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

### Restrict a service to VPN only

The `vpn-only@file` middleware restricts access to the WireGuard subnet (`10.8.0.0/24`).

Add this label to the service's compose file:

```yaml
- traefik.http.routers.myservice-secure.middlewares=vpn-only@file,security-headers@file
```

Can be combined with Authelia (VPN + login):

```yaml
- traefik.http.routers.myservice-secure.middlewares=vpn-only@file,authelia-auth@file,security-headers@file
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `WG_HOST` | Server public IP or domain (required) | - |
| `WG_PORT` | WireGuard UDP port | `51820` |
| `WG_DEFAULT_DNS` | DNS servers for clients (`10.8.0.1` = wg-dns sidecar) | `1.1.1.1, 8.8.8.8` |
| `WG_ALLOWED_IPS` | IPs routed through VPN | `0.0.0.0/0` (full tunnel) |
| `WG_PERSISTENT_KEEPALIVE` | Keepalive interval (seconds) | `25` |
| `WG_LOCAL_TARGET_IP` | IP answered for `*.local.barlito.fr` by wg-dns | `172.18.0.1` (docker_gwbridge) |
| `WG_DNS_UPSTREAM` | Upstream resolver for everything else | `1.1.1.1` |

### Access local dev sites from your phone (wg-dns)

`*.local.barlito.fr` publicly resolves to `127.0.0.1` (each dev machine reaches itself). For a phone or laptop connected through WireGuard, the `wg-dns` sidecar (dnsmasq sharing wg-easy's network namespace, listening on `10.8.0.1`) overrides that: it answers `*.local.barlito.fr` with `WG_LOCAL_TARGET_IP` and forwards everything else upstream. Public DNS is untouched.

`WG_LOCAL_TARGET_IP` depends on where wg-easy runs:

- **wg-easy on the dev machine itself**: keep the default `172.18.0.1` (docker_gwbridge gateway → the host-published 80/443 of the local Traefik).
- **wg-easy hosted on the prod server** (`deploy-vpn.yml`): set it to the WireGuard IP of the **dev machine's client profile** (e.g. `10.8.0.2`). The phone reaches the dev machine client-to-client through the server (`FORWARD` on `wg0` is already allowed), so the dev machine must keep its own VPN session up.

```bash
# 1. In .env.local: WG_DEFAULT_DNS=10.8.0.1  (and WG_LOCAL_TARGET_IP, see above)
# 2. make wireguard-up
# 3. Re-create the phone's client profile in the wg-easy UI (DNS is baked into the profile)
```

The phone then browses `https://doghelp.local.barlito.fr` through the tunnel, with the wildcard cert. Combined with the DNS-01 wildcard above: green padlock everywhere, nothing exposed to the internet.

### Split Tunnel

By default, all client traffic goes through the VPN (`0.0.0.0/0`). To only route traffic to the server (split tunnel), edit `AllowedIPs` in the client config:

```ini
AllowedIPs = 10.8.0.0/24, <SERVER_PUBLIC_IP>/32
```

## Security

Production deployment includes:

- ✅ Dashboard protected with Authelia (forwardAuth + TOTP/WebAuthn support)
- ✅ Automatic HTTP → HTTPS redirect
- ✅ Security headers (HSTS with preload, X-Frame-Options, etc.)
- ✅ INFO log level (no verbose debug logs)
- ✅ Let's Encrypt with automatic renewal
- ✅ TLS 1.2+ only with secure cipher suites
- ✅ JSON access logs to stdout (4xx/5xx errors only)

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

All logs are sent to **stdout** for Docker-native logging:

```bash
# View all logs (local or prod)
make logs

# Or directly with docker
docker service logs -f traefik_traefik
```

**For centralized logging**, no configuration is needed: the [observability-stack](https://github.com/barlito/observability-stack) runs an Alloy agent on each node that discovers every container through the Docker socket and ships stdout/stderr to Loki automatically. Logs are queryable in Grafana with labels `container`, `service` and `stack` (e.g. `{service="traefik_traefik"}`).

### Metrics

To expose Prometheus metrics, add to `traefik.yml`:

```yaml
metrics:
  prometheus:
    addEntryPointsLabels: true
    addServicesLabels: true
```

## Migration

Upgrading from a previous configuration? See [docs/MIGRATION.md](docs/MIGRATION.md)

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

Regenerate certificates:
```bash
mkcert -cert-file certs/local-cert.pem -key-file certs/local-key.pem "*.local.barlito.fr"
```

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
├── .env.local                   # Local configuration
├── docker-compose.yml           # Base configuration (common)
├── docker-compose.local.yml     # Local override for Linux (bind mounts, HTTP/3)
├── docker-compose.wsl.yml       # Local override for WSL (bind mounts, no HTTP/3)
├── docker-compose.prod.yml      # Production override (Docker configs)
├── docker-compose.wireguard.yml # WireGuard VPN (standalone, docker compose)
├── traefik.local.yml            # Local static config (DEBUG, no Let's Encrypt)
├── traefik.prod.yml             # Production static config (INFO, Let's Encrypt)
├── traefik-dynamic.local.yml    # Local dynamic config (no auth)
├── traefik-dynamic.prod.yml     # Production dynamic config (with auth)
├── authelia/                    # Authelia configuration
│   ├── configuration.local.yml  # Local config (debug, local domain)
│   ├── configuration.prod.yml   # Production config (info, prod domain)
│   └── users.yml                # User database (password hash injected by CI)
├── Makefile                  # Deployment commands (auto-detects WSL/Linux)
├── certs/                    # Local certificates (mkcert)
├── docs/                     # Documentation
│   ├── SECURITY_HEADERS.md   # Security headers explained
│   ├── GITHUB_ACTIONS.md     # CI/CD setup guide
│   └── MIGRATION.md          # Migration guide
└── scripts/
    └── generate-secrets.sh   # Secret generation helper
```

## License

MIT
