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

# Detect user and group IDs
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)
DOCKER_GROUP_ID=$(getent group docker | cut -d: -f3)

if [ -z "$DOCKER_GROUP_ID" ]; then
    echo "WARNING: Could not detect Docker group ID. Using default 999"
    DOCKER_GROUP_ID=999
fi

echo "Detected user: $CURRENT_UID:$CURRENT_GID"
echo "Detected Docker group: $DOCKER_GROUP_ID"
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

        # Add detected UID/GID values to .env
        echo "" >> "$ENV_FILE"
        echo "# User and group IDs (auto-detected)" >> "$ENV_FILE"
        echo "UID=$CURRENT_UID" >> "$ENV_FILE"
        echo "GID=$CURRENT_GID" >> "$ENV_FILE"
        echo "DOCKER_GID=$DOCKER_GROUP_ID" >> "$ENV_FILE"
        echo "SOCKET_UID=65534" >> "$ENV_FILE"

        echo "IMPORTANT: Edit .env and set your actual values:"
        echo "  - DOMAIN=your-domain.com"
        echo "  - CF_DNS_API_TOKEN=your_actual_token"
    else
        echo ""
        echo "WARNING: .env.example not found. Creating minimal .env file..."
        cat > "$ENV_FILE" << EOF
# Domain name for Traefik dashboard and services
DOMAIN=example.com

# Cloudflare DNS API Token
CF_DNS_API_TOKEN=your_cloudflare_api_token_here

# User and group IDs (auto-detected)
UID=$CURRENT_UID
GID=$CURRENT_GID
DOCKER_GID=$DOCKER_GROUP_ID
SOCKET_UID=65534
EOF
        echo "IMPORTANT: Edit .env and set your actual values!"
    fi
fi

# 8. Create letsencrypt directory and acme.json
echo ""
echo "Setting up Let's Encrypt directory..."
mkdir -p "$LETSENCRYPT_DIR"
chown "$CURRENT_UID:$CURRENT_GID" "$LETSENCRYPT_DIR"

if [ -f "$ACME_FILE" ]; then
    echo "acme.json already exists. Verifying permissions and ownership..."
else
    echo "Creating acme.json..."
    touch "$ACME_FILE"
fi

chmod 600 "$ACME_FILE"
chown "$CURRENT_UID:$CURRENT_GID" "$ACME_FILE"
echo "acme.json permissions set to 600 and ownership set to $CURRENT_UID:$CURRENT_GID"

# 9. Create logs directory
echo ""
echo "Setting up logs directory..."
mkdir -p "$LOGS_DIR"
chown "$CURRENT_UID:$CURRENT_GID" "$LOGS_DIR"
echo "logs directory ownership set to $CURRENT_UID:$CURRENT_GID"

# 10. Verify traefik network exists
echo ""
echo "Checking for traefik network..."
if docker network inspect traefik >/dev/null 2>&1; then
    echo "traefik network already exists"
else
    echo "Creating traefik network..."
    docker network create traefik
fi

# 11. Switch Authelia to production configuration
echo ""
echo "Configuring Authelia for production..."
sed -i 's/^      - \.\/authelia\/config\/configuration-local\.yml:\/config\/configuration\.yml:ro$/      # - .\/authelia\/config\/configuration-local.yml:\/config\/configuration.yml:ro/' "$COMPOSE_FILE"
sed -i 's/^      # - \.\/authelia\/config\/configuration-prod\.yml:\/config\/configuration\.yml:ro  # Uncomment for production$/      - .\/authelia\/config\/configuration-prod.yml:\/config\/configuration.yml:ro  # Uncomment for production/' "$COMPOSE_FILE"

# 12. Uncomment Authelia SMTP environment variables
sed -i 's/^      # - SMTP_HOST=\${SMTP_HOST}$/      - SMTP_HOST=\${SMTP_HOST}/' "$COMPOSE_FILE"
sed -i 's/^      # - SMTP_PORT=\${SMTP_PORT}$/      - SMTP_PORT=\${SMTP_PORT}/' "$COMPOSE_FILE"
sed -i 's/^      # - SMTP_USERNAME=\${SMTP_USERNAME}$/      - SMTP_USERNAME=\${SMTP_USERNAME}/' "$COMPOSE_FILE"
sed -i 's/^      # - SMTP_PASSWORD=\${SMTP_PASSWORD}$/      - SMTP_PASSWORD=\${SMTP_PASSWORD}/' "$COMPOSE_FILE"
sed -i 's/^      # - SMTP_FROM=\${SMTP_FROM}$/      - SMTP_FROM=\${SMTP_FROM}/' "$COMPOSE_FILE"
sed -i 's/^      # - ADMIN_EMAIL=\${ADMIN_EMAIL}$/      - ADMIN_EMAIL=\${ADMIN_EMAIL}/' "$COMPOSE_FILE"
sed -i 's/^      # - DOMAIN=\${DOMAIN}$/      - DOMAIN=\${DOMAIN}/' "$COMPOSE_FILE"

# 13. Substitute template placeholders in Authelia configuration
echo ""
echo "Substituting template placeholders in Authelia configuration..."
if [ -f "$ENV_FILE" ]; then
    # Source the .env file to get variable values
    set -a
    source "$ENV_FILE"
    set +a

    # Substitute placeholders in configuration-prod.yml
    AUTHELIA_CONFIG="${SCRIPT_DIR}/authelia/config/configuration-prod.yml"
    if [ -f "$AUTHELIA_CONFIG" ]; then
        echo "Updating $AUTHELIA_CONFIG..."
        sed -i \
            -e "s/{{DOMAIN}}/${DOMAIN}/g" \
            -e "s/{{SMTP_HOST}}/${SMTP_HOST}/g" \
            -e "s/{{SMTP_PORT}}/${SMTP_PORT}/g" \
            -e "s/{{SMTP_USERNAME}}/${SMTP_USERNAME}/g" \
            -e "s/{{SMTP_PASSWORD}}/${SMTP_PASSWORD}/g" \
            -e "s/{{SMTP_FROM}}/${SMTP_FROM}/g" \
            -e "s/{{ADMIN_EMAIL}}/${ADMIN_EMAIL}/g" \
            "$AUTHELIA_CONFIG"

        # Fix port to be integer (remove quotes if present)
        sed -i 's/port: "587"/port: 587/' "$AUTHELIA_CONFIG"

        echo "Authelia configuration updated with values from .env"
    else
        echo "WARNING: $AUTHELIA_CONFIG not found"
    fi

    # Substitute placeholders in Traefik middleware configuration
    MIDDLEWARE_CONFIG="${SCRIPT_DIR}/config/conf/authelia-middleware.yaml"
    if [ -f "$MIDDLEWARE_CONFIG" ]; then
        echo "Updating $MIDDLEWARE_CONFIG..."
        sed -i "s/authelia\.example\.com/authelia.${DOMAIN}/g" "$MIDDLEWARE_CONFIG"
        echo "Traefik middleware configuration updated with values from .env"
    else
        echo "WARNING: $MIDDLEWARE_CONFIG not found"
    fi
else
    echo "WARNING: .env file not found. Skipping template substitution."
    echo "Please run this script again after creating the .env file."
fi

echo ""
echo "=== Production Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Edit .env and set your actual values:"
echo "   - DOMAIN=your-domain.com"
echo "   - CF_DNS_API_TOKEN=your_actual_token"
echo "   - SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD (for Authelia email notifications)"
echo "   - SMTP_FROM and ADMIN_EMAIL"
echo "2. Ensure config/traefik-prod.yaml exists and is properly configured"
echo "3. Ensure Authelia is initialized: ./setup-authelia.sh"
echo "4. Run: docker compose up -d"
echo ""
echo "Backup saved at: $BACKUP_FILE"
echo "To revert: cp $BACKUP_FILE $COMPOSE_FILE"
