#!/bin/bash

# Script to generate secrets for production deployment
# Usage: ./scripts/generate-secrets.sh

set -e

echo "Traefik Production Secrets Generator"
echo "========================================"
echo ""

# Generate Authentik secrets
AUTHENTIK_SECRET_KEY=$(openssl rand -base64 36)
AUTHENTIK_DB_PASSWORD=$(openssl rand -base64 24)

echo "Generated Authentik secrets."
echo ""

# Email for Let's Encrypt
read -p "Enter email for Let's Encrypt: " email

if [ -z "$email" ]; then
    echo "Email cannot be empty"
    exit 1
fi

# Dashboard host
read -p "Enter dashboard hostname [traefik.barlito.fr]: " host
host=${host:-traefik.barlito.fr}

echo ""
echo "======================================"
echo "Secrets for GitHub Actions"
echo "======================================"
echo ""
echo "Add these to GitHub -> Settings -> Secrets -> Actions:"
echo ""
echo "AUTHENTIK_SECRET_KEY:"
echo "$AUTHENTIK_SECRET_KEY"
echo ""
echo "AUTHENTIK_DB_PASSWORD:"
echo "$AUTHENTIK_DB_PASSWORD"
echo ""
echo "DASHBOARD_HOST:"
echo "$host"
echo ""
echo "ACME_EMAIL:"
echo "$email"
echo ""
echo "======================================"
echo ""
echo "Next steps:"
echo "1. Go to GitHub -> Settings -> Secrets and variables -> Actions"
echo "2. Add the secrets above as 'Repository secrets'"
echo "3. Add these variables as 'Repository variables':"
echo "   - SERVER_USERNAME (your SSH user)"
echo "   - SERVER_HOST (your server hostname/IP)"
echo "   - SERVER_PORT (SSH port, default: 22)"
echo ""
echo "4. Add SSH_PRIVATE_KEY secret with your private key:"
echo "   cat ~/.ssh/id_ed25519"
echo ""
echo "Done!"
