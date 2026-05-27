#!/bin/bash

# Script to generate secrets for production deployment
# Usage: ./scripts/generate-secrets.sh

set -e

echo "Traefik Production Secrets Generator"
echo "========================================"
echo ""

# Generate Authelia secrets
AUTHELIA_JWT_SECRET=$(openssl rand -base64 32)
AUTHELIA_SESSION_SECRET=$(openssl rand -base64 32)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -base64 32)

echo "Generated Authelia secrets."
echo ""

# Authelia user password
read -sp "Enter Authelia password for your user: " auth_password
echo ""

if [ -z "$auth_password" ]; then
    echo "Password cannot be empty"
    exit 1
fi

echo ""
echo "Generating password hash (this may take a moment)..."
PASSWORD_HASH=$(docker run --rm authelia/authelia:4 authelia crypto hash generate argon2 --password "$auth_password" 2>/dev/null | grep 'Digest:' | awk '{print $2}')

if [ -z "$PASSWORD_HASH" ]; then
    echo "Failed to generate password hash. Make sure Docker is running."
    exit 1
fi

echo "Password hash generated."
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
echo "AUTHELIA_JWT_SECRET:"
echo "$AUTHELIA_JWT_SECRET"
echo ""
echo "AUTHELIA_SESSION_SECRET:"
echo "$AUTHELIA_SESSION_SECRET"
echo ""
echo "AUTHELIA_STORAGE_ENCRYPTION_KEY:"
echo "$AUTHELIA_STORAGE_ENCRYPTION_KEY"
echo ""
echo "AUTHELIA_USER_PASSWORD_HASH:"
echo "$PASSWORD_HASH"
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
echo "2. Add ALL the secrets above as 'Repository secrets'"
echo "3. Add SSH_PRIVATE_KEY secret with your private key:"
echo "   cat ~/.ssh/id_ed25519"
echo ""
echo "Done!"
