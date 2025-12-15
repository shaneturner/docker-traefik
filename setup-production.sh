#!/bin/bash
set -e

# Traefik Production Setup Script
# This script configures compose.yaml for production and sets up required directories/files

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"
ENV_EXAMPLE="${SCRIPT_DIR}/.env.example"
ENV_FILE="${SCRIPT_DIR}/.env"
LETSENCRYPT_DIR="${SCRIPT_DIR}/letsencrypt"
LOGS_DIR="${SCRIPT_DIR}/logs"
ACME_FILE="${LETSENCRYPT_DIR}/acme.json"

echo "=== Traefik Production Setup ==="
echo ""

# Check if compose.yaml exists
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "ERROR: compose.yaml not found at $COMPOSE_FILE"
    exit 1
fi

# Backup compose.yaml
BACKUP_FILE="${COMPOSE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup: $BACKUP_FILE"
cp "$COMPOSE_FILE" "$BACKUP_FILE"

# 1. Uncomment port 443
echo "Configuring ports..."
sed -i 's/^      # - "443:443"  # Uncomment for production$/      - "443:443"  # Uncomment for production/' "$COMPOSE_FILE"

# 2. Comment out traefik-local.yaml
echo "Switching to production config..."
sed -i 's/^      - \.\/config\/traefik-local\.yaml:\/etc\/traefik\/traefik\.yaml:ro$/      # - .\/config\/traefik-local.yaml:\/etc\/traefik\/traefik.yaml:ro/' "$COMPOSE_FILE"

# 3. Uncomment traefik-prod.yaml
sed -i 's/^      # - \.\/config\/traefik-prod\.yaml:\/etc\/traefik\/traefik\.yaml:ro  # Uncomment for production (and comment out local)$/      - .\/config\/traefik-prod.yaml:\/etc\/traefik\/traefik.yaml:ro  # Uncomment for production (and comment out local)/' "$COMPOSE_FILE"

# 4. Uncomment letsencrypt volume
echo "Enabling production volumes..."
sed -i 's/^      # - \.\/letsencrypt:\/letsencrypt  # Uncomment for production$/      - .\/letsencrypt:\/letsencrypt  # Uncomment for production/' "$COMPOSE_FILE"

# 5. Uncomment logs volume
sed -i 's/^      # - \.\/logs:\/var\/log\/traefik  # Uncomment for production$/      - .\/logs:\/var\/log\/traefik  # Uncomment for production/' "$COMPOSE_FILE"

# 6. Uncomment environment section
echo "Enabling Cloudflare DNS environment..."
sed -i 's/^    # environment:  # Uncomment for production with Cloudflare DNS challenge$/    environment:  # Uncomment for production with Cloudflare DNS challenge/' "$COMPOSE_FILE"
sed -i 's/^    #   - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}$/      - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}/' "$COMPOSE_FILE"

# 7. Create .env file if it doesn't exist
if [ -f "$ENV_FILE" ]; then
    echo ""
    echo "WARNING: .env file already exists. Skipping creation."
    echo "Please ensure it contains DOMAIN and CF_DNS_API_TOKEN variables."
else
    if [ -f "$ENV_EXAMPLE" ]; then
        echo ""
        echo "Creating .env file from .env.example..."
        cp "$ENV_EXAMPLE" "$ENV_FILE"
        echo "IMPORTANT: Edit .env and set your actual values:"
        echo "  - DOMAIN=your-domain.com"
        echo "  - CF_DNS_API_TOKEN=your_actual_token"
    else
        echo ""
        echo "WARNING: .env.example not found. Creating minimal .env file..."
        cat > "$ENV_FILE" << 'EOF'
# Domain name for Traefik dashboard and services
DOMAIN=example.com

# Cloudflare DNS API Token
CF_DNS_API_TOKEN=your_cloudflare_api_token_here
EOF
        echo "IMPORTANT: Edit .env and set your actual values!"
    fi
fi

# 8. Create letsencrypt directory and acme.json
echo ""
echo "Setting up Let's Encrypt directory..."
mkdir -p "$LETSENCRYPT_DIR"

if [ -f "$ACME_FILE" ]; then
    echo "acme.json already exists. Verifying permissions..."
else
    echo "Creating acme.json..."
    touch "$ACME_FILE"
fi

chmod 600 "$ACME_FILE"
echo "acme.json permissions set to 600"

# 9. Create logs directory
echo ""
echo "Setting up logs directory..."
mkdir -p "$LOGS_DIR"

# 10. Verify traefik network exists
echo ""
echo "Checking for traefik network..."
if docker network inspect traefik >/dev/null 2>&1; then
    echo "traefik network already exists"
else
    echo "Creating traefik network..."
    docker network create traefik
fi

echo ""
echo "=== Production Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Edit .env and set your actual DOMAIN and CF_DNS_API_TOKEN values"
echo "2. Ensure config/traefik-prod.yaml exists and is properly configured"
echo "3. Run: docker compose up -d"
echo ""
echo "Backup saved at: $BACKUP_FILE"
echo "To revert: cp $BACKUP_FILE $COMPOSE_FILE"
