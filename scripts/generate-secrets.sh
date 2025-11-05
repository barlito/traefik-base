#!/bin/bash

# Script to generate secrets for production deployment
# Usage: ./scripts/generate-secrets.sh

set -e

echo "🔐 Traefik Production Secrets Generator"
echo "========================================"
echo ""

# Check if htpasswd is installed
if ! command -v htpasswd &> /dev/null; then
    echo "❌ htpasswd is not installed."
    echo ""
    echo "Install with:"
    echo "  Ubuntu/Debian: sudo apt install apache2-utils"
    echo "  macOS:         brew install httpd"
    echo ""
    exit 1
fi

# Generate dashboard authentication
echo "📝 Dashboard Authentication"
echo ""
read -p "Enter dashboard username [admin]: " username
username=${username:-admin}

read -sp "Enter dashboard password: " password
echo ""

if [ -z "$password" ]; then
    echo "❌ Password cannot be empty"
    exit 1
fi

# Generate htpasswd hash
DASHBOARD_AUTH=$(htpasswd -nb "$username" "$password")

echo ""
echo "✅ Generated DASHBOARD_AUTH:"
echo "$DASHBOARD_AUTH"
echo ""

# Email for Let's Encrypt
read -p "Enter email for Let's Encrypt: " email

if [ -z "$email" ]; then
    echo "❌ Email cannot be empty"
    exit 1
fi

# Dashboard host
read -p "Enter dashboard hostname [traefik.barlito.fr]: " host
host=${host:-traefik.barlito.fr}

echo ""
echo "======================================"
echo "📋 Secrets for GitHub Actions"
echo "======================================"
echo ""
echo "Add these to GitHub → Settings → Secrets → Actions:"
echo ""
echo "DASHBOARD_AUTH:"
echo "$DASHBOARD_AUTH"
echo ""
echo "DASHBOARD_HOST:"
echo "$host"
echo ""
echo "ACME_EMAIL:"
echo "$email"
echo ""
echo "======================================"
echo ""
echo "ℹ️  Next steps:"
echo "1. Go to GitHub → Settings → Secrets and variables → Actions"
echo "2. Add the secrets above as 'Repository secrets'"
echo "3. Add these variables as 'Repository variables':"
echo "   - SERVER_USERNAME (your SSH user)"
echo "   - SERVER_HOST (your server hostname/IP)"
echo "   - SERVER_PORT (SSH port, default: 22)"
echo ""
echo "4. Add SSH_PRIVATE_KEY secret with your private key:"
echo "   cat ~/.ssh/id_ed25519"
echo ""
echo "✅ Done!"
