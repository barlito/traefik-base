# GitHub Actions Deployment

Guide to automatically deploy Traefik with GitHub Actions.

## GitHub Configuration

### Repository Variables

Go to **Settings** → **Secrets and variables** → **Actions** → **Variables** and add:

| Variable | Description | Example |
|----------|-------------|---------|
| `SERVER_USERNAME` | SSH username | `root` or `deploy` |
| `SERVER_HOST` | Server hostname or IP | `server.barlito.fr` or `1.2.3.4` |
| `SERVER_PORT` | SSH port | `22` or `2222` |

### Repository Secrets

Go to **Settings** → **Secrets and variables** → **Actions** → **Secrets** and add:

| Secret | Description | Example |
|--------|-------------|---------|
| `SSH_PRIVATE_KEY` | SSH private key (ed25519) | Content of `~/.ssh/id_ed25519` |
| `DASHBOARD_HOST` | Traefik dashboard domain | `traefik.barlito.fr` |
| `DASHBOARD_AUTH` | HTTP Basic authentication | `admin:$apr1$xyz...` |
| `ACME_EMAIL` | Let's Encrypt email | `admin@barlito.fr` |

## Generating Secrets

### 1. SSH_PRIVATE_KEY

On your local machine:
```bash
# Generate a new key pair (if you don't have one)
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions

# Copy public key to server
ssh-copy-id -i ~/.ssh/github_actions.pub user@server.barlito.fr

# Copy private key (to add to GitHub Secrets)
cat ~/.ssh/github_actions
```

### 2. DASHBOARD_AUTH

```bash
# Install htpasswd (if not already installed)
sudo apt install apache2-utils  # Debian/Ubuntu
# or
brew install httpd              # macOS

# Generate hash (replace 'password' with your secure password)
htpasswd -nb admin your_secure_password

# Example output:
# admin:$apr1$xyz123...$abc456...
# Copy the ENTIRE line to GitHub Secrets
```

**Important**: The `$` in the hash must be escaped as `$$` in docker-compose, but NOT in GitHub Secrets!

## Workflow

File: `.github/workflows/deploy.yml`

**Ultra-simple deployment with Docker configs**:
- Uses `DOCKER_HOST` to connect to remote Docker daemon via SSH
- Docker configs transfer files automatically (no rsync!)
- Passes variables directly to `docker stack deploy` (no `.env` file)
- `docker stack deploy` automatically updates if stack exists

**How it works**:
1. ✅ Checkout code from repository
2. ✅ Setup SSH connection with private key
3. ✅ Deploy with `make deploy-prod` (uses DOCKER_HOST)
4. ✅ Verify deployment

Docker handles transferring config files via the API - no file sync needed!

The workflow uses the Makefile command for consistency - same command for manual and automated deployments.

## Usage

### Automatic Deployment (on push)
Push to `master` branch:
```bash
git add .
git commit -m "Update traefik config"
git push origin master
```

Workflow triggers automatically and **updates** the existing stack.

### Manual Deployment
1. Go to **Actions** on GitHub
2. Select "Deploy Traefik Stack" workflow
3. Click **Run workflow**
4. Select branch and click "Run workflow"

Note: `docker stack deploy` automatically updates the stack if it already exists.

## Deployment Structure

```
Target server: /opt/traefik/
├── docker-compose.yml
├── traefik.yml
├── traefik-dynamic.prod.yml    # Used automatically
├── Makefile
├── certs/
├── logs/
└── (no .env.production file)
```

## Security

### ✅ Applied Best Practices

1. **Secrets never in code**: All secrets in GitHub Secrets
2. **Dedicated SSH key**: Separate key for automated deployments
3. **No .env committed**: `.env.production` file never in git
4. **Ephemeral variables**: Variables passed directly

### 🔒 Improving Security

```yaml
# Limit workflow to certain users
on:
  push:
    branches:
      - master
  workflow_dispatch:
    # Only certain users can trigger manually

# Add protected environments
jobs:
  deploy:
    environment:
      name: production
      url: https://traefik.barlito.fr
    # Requires manual approval before deployment
```

## Docker Configs vs Bind Mounts

This project uses different strategies for local and production:

### Local Development (`docker-compose.local.yml`)
```yaml
volumes:
  - ./traefik.local.yml:/etc/traefik/traefik.yml  # Bind mount
  - ./logs:/var/log/traefik                        # Bind mount
```
**Why?** Easy to edit configs and view logs directly on your machine.

### Production (`docker-compose.prod.yml`)
```yaml
configs:
  traefik_static:
    file: ./traefik.prod.yml  # Docker config
volumes:
  - traefik-logs:/var/log/traefik  # Docker volume
```
**Why?** Docker transfers configs via API (no file sync!), logs in managed volume.

### Deployment Flow

1. GitHub runner has `traefik.prod.yml` locally
2. `docker stack deploy` reads the file
3. Docker sends it to the server via DOCKER_HOST
4. Swarm stores it and mounts in container

**Zero file sync needed!** 🎉

## Troubleshooting

### Workflow fails with "Permission denied"
- Verify SSH public key is on the server
- Check permissions: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`

### Environment variables not interpolated
- In docker-compose, use `${VAR}` not `$VAR`
- Verify variables are exported before `docker stack deploy`

### Dashboard inaccessible after deployment
- Check DNS: `dig traefik.barlito.fr`
- Verify Let's Encrypt generated certificate: `docker exec <container> ls /etc/traefik/acme.json`
- View logs: `docker service logs traefik_traefik`

## Deployment Monitoring

Add notifications:

```yaml
- name: Notify on failure
  if: failure()
  uses: actions/github-script@v7
  with:
    script: |
      github.rest.issues.create({
        owner: context.repo.owner,
        repo: context.repo.repo,
        title: '❌ Traefik deployment failed',
        body: 'Deployment failed. Check the Actions tab for details.'
      })
```

Or integrate with Slack, Discord, etc.

## Helper Script

Use the provided script to generate secrets:

```bash
./scripts/generate-secrets.sh
```

This will:
- Generate `DASHBOARD_AUTH` with htpasswd
- Collect required configuration values
- Display formatted values ready to paste into GitHub Secrets
- Provide next steps for completing the setup
