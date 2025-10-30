# GitHub Actions Deployment

Guide to automatically deploy Traefik with GitHub Actions.

## GitHub Secrets Configuration

Go to **Settings** → **Secrets and variables** → **Actions** and add:

### Required Secrets

| Secret | Description | Example |
|--------|-------------|---------|
| `SSH_PRIVATE_KEY` | SSH private key to connect to server | Content of `~/.ssh/id_rsa` |
| `SSH_USER` | SSH username | `root` or `deploy` |
| `SERVER_HOST` | Server hostname or IP | `server.barlito.fr` or `1.2.3.4` |
| `DASHBOARD_HOST` | Traefik dashboard domain | `traefik.barlito.fr` |
| `DASHBOARD_AUTH` | HTTP Basic authentication | Generated with `htpasswd -nb admin password` |
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

**Features**:
- Passes variables directly to `docker stack deploy`
- No `.env` file created on server
- More secure (no temporary file with secrets)

## Usage

### Automatic Deployment
Push to `master` branch:
```bash
git add .
git commit -m "Update traefik config"
git push origin master
```

Workflow triggers automatically.

### Manual Deployment
1. Go to **Actions** on GitHub
2. Select "Deploy Traefik Stack" workflow
3. Click **Run workflow**
4. Select branch and run

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

## Alternative: Docker Context Deployment

If you prefer deploying directly from GitHub Actions without SSH:

```yaml
- name: Setup Docker Context
  run: |
    docker context create remote --docker "host=ssh://${{ secrets.SSH_USER }}@${{ secrets.SERVER_HOST }}"
    docker context use remote

- name: Deploy Stack
  env:
    ENV: production
    DASHBOARD_HOST: ${{ secrets.DASHBOARD_HOST }}
    # ... other vars
  run: |
    docker stack deploy -c docker-compose.yml traefik
```

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
- Display formatted values for GitHub Secrets
- Optionally create `.env.production` for manual deployments
