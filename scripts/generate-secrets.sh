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

# Optionally create .env.production
read -p "Create .env.production file? [y/N]: " create_env

if [[ "$create_env" =~ ^[Yy]$ ]]; then
    cat > .env.production << EOF
# Production Environment
ENV=production
TRAEFIK_IMAGE=traefik:3.0
DASHBOARD_HOST=$host

# Dashboard Authentication
DASHBOARD_AUTH=$DASHBOARD_AUTH

# Let's Encrypt Configuration
ACME_EMAIL=$email
EOF

    echo "✅ Created .env.production"
    echo "⚠️  WARNING: This file contains sensitive data!"
    echo "   - Do NOT commit it to git (it's in .gitignore)"
    echo "   - Use only for manual deployments"
    echo "   - For GitHub Actions, use Secrets instead"
else
    echo "ℹ️  .env.production not created. Use GitHub Secrets for deployment."
fi

echo ""
echo "✅ Done!"
