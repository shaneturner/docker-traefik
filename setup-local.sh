#!/bin/bash
set -e

# Traefik Local Development Setup Script
# This script reverts compose.yaml to local development configuration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"

echo "=== Traefik Local Development Setup ==="
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

# 1. Comment out port 443
echo "Configuring ports for local development..."
sed -i 's/^      - "443:443"  # Uncomment for production$/      # - "443:443"  # Uncomment for production/' "$COMPOSE_FILE"

# 2. Uncomment traefik-local.yaml
echo "Switching to local config..."
sed -i 's/^      # - \.\/config\/traefik-local\.yaml:\/etc\/traefik\/traefik\.yaml:ro$/      - .\/config\/traefik-local.yaml:\/etc\/traefik\/traefik.yaml:ro/' "$COMPOSE_FILE"

# 3. Comment out traefik-prod.yaml
sed -i 's/^      - \.\/config\/traefik-prod\.yaml:\/etc\/traefik\/traefik\.yaml:ro  # Uncomment for production (and comment out local)$/      # - .\/config\/traefik-prod.yaml:\/etc\/traefik\/traefik.yaml:ro  # Uncomment for production (and comment out local)/' "$COMPOSE_FILE"

# 4. Comment out letsencrypt volume
echo "Disabling production volumes..."
sed -i 's/^      - \.\/letsencrypt:\/letsencrypt  # Uncomment for production$/      # - .\/letsencrypt:\/letsencrypt  # Uncomment for production/' "$COMPOSE_FILE"

# 5. Comment out logs volume
sed -i 's/^      - \.\/logs:\/var\/log\/traefik  # Uncomment for production$/      # - .\/logs:\/var\/log\/traefik  # Uncomment for production/' "$COMPOSE_FILE"

# 6. Comment out environment section
echo "Disabling Cloudflare DNS environment..."
sed -i 's/^    environment:  # Uncomment for production with Cloudflare DNS challenge$/    # environment:  # Uncomment for production with Cloudflare DNS challenge/' "$COMPOSE_FILE"
sed -i 's/^      - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}$/    #   - CF_DNS_API_TOKEN=\${CF_DNS_API_TOKEN}/' "$COMPOSE_FILE"

# 7. Verify traefik network exists
echo ""
echo "Checking for traefik network..."
if docker network inspect traefik >/dev/null 2>&1; then
    echo "traefik network already exists"
else
    echo "Creating traefik network..."
    docker network create traefik
fi

echo ""
echo "=== Local Development Setup Complete ==="
echo ""
echo "Next steps:"
echo "1. Run: docker compose up -d"
echo "2. Access dashboard at: http://traefik.localhost"
echo ""
echo "Backup saved at: $BACKUP_FILE"
echo "To revert: cp $BACKUP_FILE $COMPOSE_FILE"
