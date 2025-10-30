# Traefik Base Configuration

Production-ready Traefik 3.0 setup with separate local/production configurations.

## Features

- 🚀 HTTP/3 support
- 🔒 Automatic HTTP → HTTPS redirect
- 🛡️ Security headers (HSTS, X-Frame-Options, CSP, etc.)
- 🔐 Secure dashboard (auth in production only)
- 📜 Let's Encrypt automatic certificates
- 📊 Structured JSON access logs
- 🌍 Environment-based configuration (local/production)

## Quick Start

### Local Development

```bash
# 1. Copy local configuration
cp .env.example .env.local

# 2. Generate local certificates (if expired)
mkdir -p certs
mkcert -cert-file certs/local-cert.pem -key-file certs/local-key.pem "*.local.barlito.fr"

# 3. Create logs directory
mkdir -p logs

# 4. Deploy
make deploy
```

Dashboard: https://traefik.local.barlito.fr (no authentication required)

### Production

```bash
# 1. Generate production secrets
./scripts/generate-secrets.sh

# 2. Deploy to production
make deploy ENV=prod
```

Dashboard: https://traefik.barlito.fr (HTTP Basic authentication required)

## Available Commands

```bash
make help           # Show help message
make deploy         # Deploy locally (default)
make deploy ENV=prod # Deploy to production
make undeploy       # Remove the stack
make logs           # Follow Traefik logs
make restart        # Restart the stack
```

## Configuration

### Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ENV` | Environment (local/production) | `local` |
| `DASHBOARD_HOST` | Dashboard domain | `traefik.barlito.fr` |
| `DASHBOARD_AUTH` | HTTP Basic auth (prod only) | `admin:$apr1$...` |
| `ACME_EMAIL` | Let's Encrypt email (prod only) | `admin@example.com` |

### Configuration Files

- `traefik.local.yml` - Local static configuration (no Let's Encrypt, DEBUG logs)
- `traefik.prod.yml` - Production static configuration (Let's Encrypt, INFO logs)
- `traefik-dynamic.local.yml` - Local dynamic config (no auth)
- `traefik-dynamic.prod.yml` - Production dynamic config (with auth)
- `docker-compose.yml` - Docker Swarm stack

### Certificates

**Local**: Self-signed certificates using [mkcert](https://github.com/FiloSottile/mkcert)

**Production**: Automatic Let's Encrypt via HTTP challenge

## Security

Production deployment includes:

- ✅ Dashboard protected with HTTP Basic authentication
- ✅ Automatic HTTP → HTTPS redirect
- ✅ Security headers (HSTS with preload, X-Frame-Options, etc.)
- ✅ INFO log level (no verbose debug logs)
- ✅ Let's Encrypt with automatic renewal
- ✅ TLS 1.2+ only with secure cipher suites
- ✅ JSON access logs (4xx/5xx errors only)

For detailed security headers explanation, see [docs/SECURITY_HEADERS.md](docs/SECURITY_HEADERS.md)

## Automated Deployment (GitHub Actions)

Deploy automatically from GitHub using secrets management.

See [docs/GITHUB_ACTIONS.md](docs/GITHUB_ACTIONS.md) for setup instructions.

**Benefits**:
- No `.env.production` file in repository
- Secrets managed by GitHub
- Automatic deployment on push
- Deployment traceability

## Monitoring

Access logs are available in `./logs/` directory in JSON format for easy integration with Grafana/Loki.

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
├── .env.example              # Environment template
├── .env.local                # Local configuration
├── docker-compose.yml        # Docker Swarm stack
├── traefik.local.yml         # Local static config (no Let's Encrypt)
├── traefik.prod.yml          # Production static config (with Let's Encrypt)
├── traefik-dynamic.local.yml # Local dynamic config (no auth)
├── traefik-dynamic.prod.yml  # Production dynamic config (with auth)
├── Makefile                  # Deployment commands
├── certs/                    # Local certificates (mkcert)
├── logs/                     # Access logs
├── docs/                     # Documentation
│   ├── SECURITY_HEADERS.md   # Security headers explained
│   ├── GITHUB_ACTIONS.md     # CI/CD setup guide
│   └── MIGRATION.md          # Migration guide
└── scripts/
    └── generate-secrets.sh   # Secret generation helper
```

## License

MIT
