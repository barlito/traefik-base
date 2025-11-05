# Migration Guide

Guide to migrate from the old configuration to the new one with local/production support.

## Main Changes

### Added Files
```
.env.example                    # Configuration template
.env.local                      # Local configuration
.env.production                 # Production configuration (to create)
traefik-dynamic.local.yml       # Local dynamic config (no auth)
traefik-dynamic.prod.yml        # Production dynamic config (with auth)
docs/SECURITY_HEADERS.md        # Security headers documentation
docs/GITHUB_ACTIONS.md          # CI/CD setup guide
docs/MIGRATION.md               # This migration guide
scripts/generate-secrets.sh     # Secret generation helper
.github/workflows/deploy.yml    # GitHub Actions workflow
```

### Modified Files
```
docker-compose.yml              # Environment variables support
traefik.yml                     # Dynamic logs, Let's Encrypt
Makefile                        # Improved commands
README.md                       # Complete documentation
.gitignore                      # Secrets exclusion
```

### Deprecated Files
```
traefik-dynamic.yml → traefik-dynamic.yml.old (backup)
```

## Step-by-Step Migration

### 1. Backup Existing Config (already done)
```bash
# Old file has been automatically renamed
traefik-dynamic.yml → traefik-dynamic.yml.old
```

### 2. Local Configuration

If you're currently deploying locally:

```bash
# 1. Create local config
cp .env.example .env.local

# 2. Test deployment
make undeploy  # Stop old stack
make deploy    # Start new (uses .env.local by default)
```

Verifications:
- Dashboard accessible: https://traefik.local.barlito.fr
- No authentication requested (normal for local)
- HTTP → HTTPS redirect works

### 3. Production Configuration

If you're deploying to production:

```bash
# Option 1: With helper script
./scripts/generate-secrets.sh

# Option 2: Manually
cp .env.example .env.production
# Edit .env.production with your values
```

**Important values to configure**:
- `DASHBOARD_HOST`: Your production domain (e.g., traefik.barlito.fr)
- `DASHBOARD_AUTH`: Generate with `htpasswd -nb admin your_password`
- `ACME_EMAIL`: Your email for Let's Encrypt

Deployment:
```bash
make deploy ENV=prod
```

## Behavior Differences

### Before (old config)
```yaml
# Logs always in DEBUG
log:
    level: DEBUG

# No automatic HTTP → HTTPS redirect
# No security headers
# Dashboard without authentication
# Let's Encrypt not configured
```

### After (new config)

**Locally**:
```yaml
# Logs in DEBUG for easier development
log:
    level: DEBUG

# HTTP → HTTPS redirect ✅
# Security headers ✅
# Dashboard WITHOUT authentication (convenient for dev)
# mkcert certificates (self-signed)
```

**Production**:
```yaml
# Logs in INFO (clean)
log:
    level: INFO

# HTTP → HTTPS redirect ✅
# Security headers ✅
# Dashboard WITH HTTP Basic authentication ✅
# Automatic Let's Encrypt ✅
# JSON access logs (errors only) ✅
```

## Backward Compatibility

### Do existing services still work?

**YES** ✅ Services already deployed with Traefik labels will continue to work without changes.

Example of an existing service:
```yaml
services:
  myapp:
    labels:
      - traefik.enable=true
      - traefik.http.routers.myapp.rule=Host(`myapp.barlito.fr`)
      - traefik.http.services.myapp.loadbalancer.server.port=8080
```

**Automatically inherited**:
- ✅ HTTP → HTTPS redirect
- ✅ Security headers
- ✅ Let's Encrypt certificate (in production)

To disable middlewares for a specific service:
```yaml
labels:
  - traefik.http.routers.myapp.middlewares=  # Empty = no middleware
```

## Rollback in Case of Problems

If the new config causes issues, roll back:

```bash
# 1. Stop new stack
make undeploy

# 2. Restore old dynamic config
mv traefik-dynamic.yml.old traefik-dynamic.yml

# 3. Edit docker-compose.yml to remove variables (optional)
# Or create a minimal .env.local

# 4. Redeploy with old method
docker stack deploy -c docker-compose.yml traefik
```

## Migration FAQ

### Q: Do I need to reconfigure all my services?
**A**: No, they continue to work as-is.

### Q: What happens if I don't create .env.local?
**A**: Default values from docker-compose.yml apply (ENV=local, LOG_LEVEL=DEBUG, etc.).

### Q: Can I use the old deployment method?
**A**: Yes, but you lose the benefits (adapted logs, conditional auth, etc.).

### Q: Will the Let's Encrypt certificate regenerate?
**A**: No if acme.json already exists. Traefik reuses existing certificates.

### Q: Will my HTTP services break with HTTPS redirect?
**A**: Traefik will redirect HTTP → HTTPS automatically. Your services don't need to support HTTPS themselves (Traefik handles TLS).

### Q: How to test without breaking production?
**A**:
```bash
# On a test/staging environment
make deploy ENV=prod  # Same config as prod but different server
```

## Post-Migration Checklist

- [ ] Dashboard accessible
- [ ] Authentication works (production only)
- [ ] HTTP → HTTPS redirect active
- [ ] Existing services still accessible
- [ ] Let's Encrypt certificates generated (production)
- [ ] Logs in `./logs/access.log` (JSON format)
- [ ] Security headers present (test with `curl -I`)

### Quick Headers Test
```bash
curl -I https://traefik.barlito.fr 2>&1 | grep -E "(X-|Strict-Transport)"
```

Expected:
```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Frame-Options: DENY
X-Content-Type-Options: nosniff
X-XSS-Protection: 1; mode=block
```

## Support

In case of problems:
1. Check logs: `make logs`
2. Check config: `docker config ls`
3. Check service: `docker service ps traefik_traefik`
4. Open an issue on the repo with error logs
