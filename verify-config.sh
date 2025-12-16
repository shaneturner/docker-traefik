#!/bin/bash

# Configuration Verification Script
# Checks for common configuration issues before deployment

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
COMPOSE_FILE="${SCRIPT_DIR}/compose.yaml"

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

echo "=== Configuration Verification ==="
echo ""

# Function to report error
error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

# Function to report warning
warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((WARNINGS++))
}

# Function to report success
success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

# Check 1: Verify .env file exists
echo "Checking environment configuration..."
if [ ! -f "$ENV_FILE" ]; then
    error ".env file not found at $ENV_FILE"
else
    success ".env file exists"

    # Source .env to check variables
    set -a
    source "$ENV_FILE" 2>/dev/null
    set +a

    # Check required variables
    [ -z "$DOMAIN" ] && error "DOMAIN not set in .env"
    [ -z "$UID" ] && warning "UID not set in .env (containers may run as root)"
    [ -z "$GID" ] && warning "GID not set in .env (containers may run as root)"
    [ -z "$DOCKER_GID" ] && warning "DOCKER_GID not set in .env (socket-proxy may fail)"
    [ -z "$SOCKET_UID" ] && warning "SOCKET_UID not set in .env"
fi

# Check 2: Verify Docker group ID matches actual system
echo ""
echo "Checking Docker group configuration..."
if command -v getent >/dev/null 2>&1; then
    ACTUAL_DOCKER_GID=$(getent group docker 2>/dev/null | cut -d: -f3)
    if [ -n "$ACTUAL_DOCKER_GID" ]; then
        if [ -n "$DOCKER_GID" ] && [ "$DOCKER_GID" != "$ACTUAL_DOCKER_GID" ]; then
            error "DOCKER_GID mismatch: .env has $DOCKER_GID, but system has $ACTUAL_DOCKER_GID"
            echo "       This will cause socket-proxy permission errors!"
            echo "       Fix: Update .env with DOCKER_GID=$ACTUAL_DOCKER_GID"
        else
            success "DOCKER_GID matches system ($ACTUAL_DOCKER_GID)"
        fi
    fi
fi

# Check 3: Scan for template placeholders in configuration files
echo ""
echo "Scanning for unsubstituted template placeholders..."

PLACEHOLDER_PATTERN='{{[A-Z_]+}}'
FOUND_PLACEHOLDERS=0

# Files to check
FILES_TO_CHECK=(
    "authelia/config/configuration-prod.yml"
    "authelia/config/configuration-local.yml"
    "config/conf/authelia-middleware.yaml"
)

for file in "${FILES_TO_CHECK[@]}"; do
    if [ -f "${SCRIPT_DIR}/${file}" ]; then
        # Search for placeholders
        MATCHES=$(grep -n "$PLACEHOLDER_PATTERN" "${SCRIPT_DIR}/${file}" 2>/dev/null || true)
        if [ -n "$MATCHES" ]; then
            error "Template placeholders found in $file:"
            echo "$MATCHES" | while IFS= read -r line; do
                echo "       $line"
            done
            ((FOUND_PLACEHOLDERS++))
        fi
    fi
done

if [ $FOUND_PLACEHOLDERS -eq 0 ]; then
    success "No unsubstituted template placeholders found"
fi

# Check 4: Verify example.com is not in production configs
echo ""
echo "Checking for example.com placeholders..."
EXAMPLE_FOUND=0

for file in "${FILES_TO_CHECK[@]}"; do
    if [[ "$file" == *"prod"* ]] && [ -f "${SCRIPT_DIR}/${file}" ]; then
        if grep -q "example\.com" "${SCRIPT_DIR}/${file}" 2>/dev/null; then
            error "Found 'example.com' in production config: $file"
            grep -n "example\.com" "${SCRIPT_DIR}/${file}" | while IFS= read -r line; do
                echo "       $line"
            done
            ((EXAMPLE_FOUND++))
        fi
    fi
done

if [ $EXAMPLE_FOUND -eq 0 ]; then
    success "No example.com placeholders found in production configs"
fi

# Check 5: Verify which Traefik config is active in compose.yaml
echo ""
echo "Checking active Traefik configuration..."
if [ -f "$COMPOSE_FILE" ]; then
    if grep -q "^      - ./config/traefik-prod.yaml:/etc/traefik/traefik.yaml:ro" "$COMPOSE_FILE"; then
        success "Production Traefik config is active"

        # Verify local is commented out
        if grep -q "^      - ./config/traefik-local.yaml:/etc/traefik/traefik.yaml:ro" "$COMPOSE_FILE"; then
            error "Both Traefik configs are active! Only one should be mounted."
        fi
    elif grep -q "^      - ./config/traefik-local.yaml:/etc/traefik/traefik.yaml:ro" "$COMPOSE_FILE"; then
        warning "Local Traefik config is active (not production)"
    else
        error "No Traefik config is active in compose.yaml"
    fi
fi

# Check 6: Verify which Authelia config is active
echo ""
echo "Checking active Authelia configuration..."
if [ -f "$COMPOSE_FILE" ]; then
    if grep -q "^      - ./authelia/config/configuration-prod.yml:/config/configuration.yml:ro" "$COMPOSE_FILE"; then
        success "Production Authelia config is active"

        # Verify local is commented out
        if grep -q "^      - ./authelia/config/configuration-local.yml:/config/configuration.yml:ro" "$COMPOSE_FILE"; then
            error "Both Authelia configs are active! Only one should be mounted."
        fi
    elif grep -q "^      - ./authelia/config/configuration-local.yml:/config/configuration.yml:ro" "$COMPOSE_FILE"; then
        warning "Local Authelia config is active (not production)"
    else
        error "No Authelia config is active in compose.yaml"
    fi
fi

# Check 7: Verify required Authelia SMTP variables for production
echo ""
echo "Checking Authelia SMTP configuration..."
if grep -q "^      - ./authelia/config/configuration-prod.yml:/config/configuration.yml:ro" "$COMPOSE_FILE" 2>/dev/null; then
    # Production mode
    [ -z "$SMTP_HOST" ] && error "SMTP_HOST not set in .env (required for production)"
    [ -z "$SMTP_PORT" ] && error "SMTP_PORT not set in .env (required for production)"
    [ -z "$SMTP_FROM" ] && error "SMTP_FROM not set in .env (required for production)"
    [ -z "$ADMIN_EMAIL" ] && error "ADMIN_EMAIL not set in .env (required for production)"

    if [ -z "$SMTP_USERNAME" ] || [ -z "$SMTP_PASSWORD" ]; then
        warning "SMTP_USERNAME or SMTP_PASSWORD not set (OK for no-auth relays)"
    fi

    if [ -n "$SMTP_HOST" ] && [ -n "$SMTP_PORT" ] && [ -n "$SMTP_FROM" ] && [ -n "$ADMIN_EMAIL" ]; then
        success "SMTP configuration appears complete"
    fi
fi

# Check 8: Verify acme.json permissions (production only)
echo ""
echo "Checking Let's Encrypt configuration..."
ACME_FILE="${SCRIPT_DIR}/letsencrypt/acme.json"
if [ -f "$ACME_FILE" ]; then
    PERMS=$(stat -c %a "$ACME_FILE" 2>/dev/null || stat -f %OLp "$ACME_FILE" 2>/dev/null)
    if [ "$PERMS" != "600" ]; then
        error "acme.json has incorrect permissions ($PERMS). Must be 600."
        echo "       Fix: chmod 600 $ACME_FILE"
    else
        success "acme.json has correct permissions (600)"
    fi
else
    if grep -q "^      - ./config/traefik-prod.yaml:/etc/traefik/traefik.yaml:ro" "$COMPOSE_FILE" 2>/dev/null; then
        warning "acme.json not found (will be created on first run)"
    fi
fi

# Check 9: Verify Traefik network exists
echo ""
echo "Checking Docker network..."
if command -v docker >/dev/null 2>&1; then
    if docker network inspect traefik >/dev/null 2>&1; then
        success "traefik network exists"
    else
        warning "traefik network does not exist"
        echo "       Create with: docker network create traefik"
    fi
else
    warning "Docker command not available, skipping network check"
fi

# Check 10: Verify Authelia is initialized
echo ""
echo "Checking Authelia initialization..."
if [ -f "${SCRIPT_DIR}/authelia/data/users_database.yml" ]; then
    success "Authelia users database exists"
elif [ -f "${SCRIPT_DIR}/authelia/config/users_database.yml" ]; then
    success "Authelia users database exists (config directory)"
else
    warning "Authelia users database not found"
    echo "       Initialize with: ./setup-authelia.sh"
fi

# Summary
echo ""
echo "=== Verification Summary ==="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC} Configuration looks good."
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s) found.${NC} Review above and fix if necessary."
    exit 0
else
    echo -e "${RED}$ERRORS error(s) found.${NC}"
    if [ $WARNINGS -gt 0 ]; then
        echo -e "${YELLOW}$WARNINGS warning(s) found.${NC}"
    fi
    echo ""
    echo "Please fix the errors before deploying to production."
    exit 1
fi
