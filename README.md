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

**Local**: Self-signed certificates using [mkcert](https://github.com/FiloSottile/mkcert)

**Production**: Automatic Let's Encrypt via HTTP challenge

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

**For centralized logging**, configure Docker logging driver to send to Loki, Fluentd, or other log aggregators:

```yaml
# In docker-compose.yml
services:
  traefik:
    logging:
      driver: loki
      options:
        loki-url: "http://loki:3100/loki/api/v1/push"
```

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
