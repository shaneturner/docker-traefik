#!/bin/bash
set -e

# Authelia Initialization Script
# This script sets up Authelia with secrets, directories, and an initial admin user

echo "==================================="
echo "Authelia Initialization Script"
echo "==================================="
echo ""

# Detect user and group IDs
CURRENT_UID=$(id -u)
CURRENT_GID=$(id -g)

echo "Detected user: UID=$CURRENT_UID, GID=$CURRENT_GID"
echo ""

# Create directory structure
echo "Creating Authelia directory structure..."
mkdir -p authelia/config
mkdir -p authelia/secrets
mkdir -p authelia/data

# Set ownership
echo "Setting directory ownership to $CURRENT_UID:$CURRENT_GID..."
chown -R "$CURRENT_UID:$CURRENT_GID" authelia/

# Set permissions
chmod 755 authelia/config
chmod 700 authelia/secrets
chmod 755 authelia/data

echo "✓ Directory structure created"
echo ""

# Generate secrets
echo "Generating cryptographic secrets..."

if [ ! -f authelia/secrets/jwt_secret ]; then
    openssl rand -hex 64 > authelia/secrets/jwt_secret
    echo "✓ Generated JWT secret"
fi

if [ ! -f authelia/secrets/session_secret ]; then
    openssl rand -hex 64 > authelia/secrets/session_secret
    echo "✓ Generated session secret"
fi

if [ ! -f authelia/secrets/storage_encryption_key ]; then
    openssl rand -hex 64 > authelia/secrets/storage_encryption_key
    echo "✓ Generated storage encryption key"
fi

# Secure permissions on secrets
chmod 600 authelia/secrets/*
echo "✓ Secrets secured with 600 permissions"
echo ""

# Create notification file for local testing
touch authelia/data/notification.txt
chmod 644 authelia/data/notification.txt
echo "✓ Created notification file for local testing"
echo ""

# Prompt for admin user details
if [ ! -f authelia/config/users_database.yml ]; then
    echo "==================================="
    echo "Admin User Setup"
    echo "==================================="
    echo ""

    read -p "Enter admin email: " ADMIN_EMAIL
    read -sp "Enter admin password: " ADMIN_PASSWORD
    echo ""
    read -sp "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
    echo ""
    echo ""

    if [ "$ADMIN_PASSWORD" != "$ADMIN_PASSWORD_CONFIRM" ]; then
        echo "ERROR: Passwords do not match!"
        exit 1
    fi

    echo "Hashing password with Argon2id (this may take a moment)..."
    PASSWORD_HASH=$(docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$ADMIN_PASSWORD" | grep '$argon2id' | sed 's/Digest: //')

    if [ -z "$PASSWORD_HASH" ]; then
        echo "ERROR: Failed to generate password hash!"
        exit 1
    fi

    echo "✓ Password hashed successfully"
    echo ""

    # Create users_database.yml
    echo "Creating users database..."
    cat > authelia/config/users_database.yml <<EOF
---
# Authelia User Database
# Users are stored in this file with Argon2id hashed passwords
# IMPORTANT: This file contains sensitive information and should never be committed to git

users:
  admin:
    displayname: "Administrator"
    password: "$PASSWORD_HASH"
    email: "$ADMIN_EMAIL"
    groups:
      - admins
      - dev
EOF

    # Set correct ownership and permissions
    chown "$CURRENT_UID:$CURRENT_GID" authelia/config/users_database.yml
    chmod 600 authelia/config/users_database.yml

    echo "✓ Admin user created"
    echo ""
else
    echo "NOTE: users_database.yml already exists, skipping admin user creation"
    echo ""
fi

# Verify .gitignore
if grep -q "authelia/secrets/" .gitignore && grep -q "authelia/data/" .gitignore; then
    echo "✓ .gitignore properly configured"
else
    echo "WARNING: .gitignore may not properly exclude sensitive Authelia files!"
    echo "Please ensure authelia/secrets/ and authelia/data/ are in .gitignore"
fi
echo ""

# Final summary
echo "==================================="
echo "✓ Authelia Initialization Complete"
echo "==================================="
echo ""
echo "Directory structure:"
echo "  authelia/config/       - Configuration files (tracked in git except users_database.yml)"
echo "  authelia/secrets/      - Cryptographic secrets (gitignored)"
echo "  authelia/data/         - Runtime data (gitignored)"
echo ""
echo "Next steps:"
echo "  1. Review authelia/config/configuration-local.yml"
echo "  2. Start the stack: docker compose up -d"
echo "  3. Access Authelia at http://authelia.localhost"
echo "  4. Access Traefik dashboard at http://traefik.localhost (will require authentication)"
echo ""
echo "To add more users:"
echo "  1. Generate hash: docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'"
echo "  2. Edit authelia/config/users_database.yml"
echo "  3. Restart Authelia: docker compose restart authelia"
echo ""
echo "IMPORTANT: Backup authelia/secrets/ and users_database.yml securely!"
echo ""
