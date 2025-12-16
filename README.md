# Docker Traefik

Docker Compose Traefik v3 reverse proxy supporting both local development and production environments with enhanced security via Docker Socket Proxy and Authelia SSO.

Uses \*.localhost for local domains with automatic HTTP routing, or custom domains in production with HTTPS via Let's Encrypt.

## Initial Setup

Follow these steps **in order** when setting up for the first time:

### 1. Create Docker Network

```bash
docker network create traefik
```

### 2. Set Up Authelia (Required)

Run the Authelia setup script to create directories, generate cryptographic secrets, and create your initial admin user:

```bash
./setup-authelia.sh
```

This script only needs to run **once** and works for both local and production environments. It will:
- Create `authelia/config/`, `authelia/secrets/`, and `authelia/data/` directories
- Generate secure random secrets (JWT, session, encryption, storage keys)
- Prompt you to create an admin user with password

### 3. Start Traefik (Local Development)

```bash
docker compose up -d
```

The Traefik dashboard is now accessible at: http://traefik.localhost

When prompted, log in with the admin credentials you created in step 2.

### 4. (Optional) Switch to Production

If deploying to production, run:

```bash
./setup-production.sh
```

Then edit `.env` to set your domain, Cloudflare API token, and SMTP credentials (see Production Deployment section below).

## Configuration

This setup uses **file-based configuration** with separate config files for local development and production environments.

### Security

This setup includes multiple layers of security:

#### Docker Socket Proxy

A **Docker Socket Proxy** ([wollomatic/socket-proxy](https://github.com/wollomatic/socket-proxy)) sits between Traefik and the Docker socket, using regex-based access control to limit Traefik's access to only the Docker API endpoints it needs (containers, networks, and events), with all write operations disabled.

**Key features:**
- Built in Go with zero dependencies (minimal attack surface)
- Regex-based permission rules for fine-grained API access control
- Hostname-based allowlisting (only the `traefik` container can connect)
- Read-only filesystem and dropped capabilities
- Socket watchdog for automatic recovery from Docker daemon issues

#### Authelia Single Sign-On (SSO)

**Authelia** provides centralized authentication and access control for the Traefik dashboard and any services routed through Traefik.

**Key features:**
- Single Sign-On (SSO) for all protected services
- Argon2id password hashing
- Two-Factor Authentication (2FA) support via TOTP
- Session-based authentication
- File-based user database (suitable for small teams)
- Access control rules per domain/path

**Configuration files:**
- `authelia/config/configuration-local.yml` - File-based notifications for local development
- `authelia/config/configuration-prod.yml` - SMTP email notifications for production
- `authelia/data/users_database.yml` - User credentials (created by `setup-authelia.sh`)

#### Non-Root Execution

Both Traefik and socket-proxy run as **non-root users**, preventing root-owned files in bind mounts:
- **Traefik**: Runs as the host user (UID/GID from .env, typically 1000:1000)
- **Socket Proxy**: Runs as user 65534 (nobody) with Docker group GID for socket access

This ensures all files in `letsencrypt/` and `logs/` are owned by your user account, eliminating the need for sudo.

### Local Development (Default)

The default configuration uses `config/traefik-local.yaml`:

- HTTP only on port 80
- Traefik dashboard accessible at http://traefik.localhost
- Debug logging enabled
- No SSL/HTTPS

**No changes needed** - just run `docker compose up -d`

### Production Deployment

**Prerequisites:** You must have already run `./setup-authelia.sh` (see Initial Setup above) before switching to production.

#### Automated Setup (Recommended)

Run the production setup script:

```bash
./setup-production.sh
```

This automatically:
- Switches from `traefik-local.yaml` to `traefik-prod.yaml`
- Switches from `authelia/configuration-local.yml` to `authelia/configuration-prod.yml`
- Enables port 443 for HTTPS
- Enables `letsencrypt` and `logs` volume mounts
- Enables Cloudflare DNS environment variables
- Enables Authelia SMTP environment variables
- Auto-detects your UID, GID, and Docker group ID
- Creates `.env` from `.env.example` with detected IDs (if not exists)
- Substitutes template placeholders in Authelia config with values from `.env`
- Creates `letsencrypt/` directory with correct ownership
- Creates `acme.json` with 600 permissions and correct ownership
- Creates `logs/` directory with correct ownership
- Verifies `traefik` network exists
- Creates a timestamped backup of `compose.yaml`

After running the script:

1. **Edit `.env`** and set your actual values:
   ```bash
   # Traefik configuration
   DOMAIN=example.com
   CF_DNS_API_TOKEN=your_cloudflare_api_token_here

   # Authelia SMTP configuration (for email notifications)
   SMTP_HOST=smtp.example.com
   SMTP_PORT=587
   SMTP_USERNAME=your_smtp_username
   SMTP_PASSWORD=your_smtp_password
   SMTP_FROM=authelia@example.com
   ADMIN_EMAIL=admin@example.com
   ```

2. **Re-run setup script** to substitute placeholders with your actual values:
   ```bash
   ./setup-production.sh
   ```

3. **Verify configuration** before deploying:
   ```bash
   ./verify-config.sh
   ```

4. **Deploy services**:
   ```bash
   docker compose down
   docker compose up -d
   ```

#### Switch Back to Local

To revert to local development configuration:

```bash
./setup-local.sh
docker compose up -d
```

#### Configuration Verification

Use the verification script to check for common configuration issues before deployment:

```bash
./verify-config.sh
```

The script checks for:
- Missing or unset environment variables in `.env`
- Unsubstituted template placeholders (e.g., `{{DOMAIN}}`, `{{SMTP_HOST}}`)
- Docker group ID mismatches that cause socket-proxy permission errors
- Hardcoded example.com domains in production configs
- Active configuration files in `compose.yaml`
- SMTP configuration for Authelia
- Let's Encrypt `acme.json` file permissions
- Docker network existence
- Authelia initialization status

**Exit codes:**
- `0` - All checks passed or only warnings found
- `1` - Errors found that must be fixed before deployment

Run this script both **before** deploying to production and **after** making any configuration changes to catch issues early.

#### Manual Setup

If you prefer to configure manually, see the detailed steps in `CLAUDE.md`.

### Configuration Files

#### Traefik Configuration
- `config/traefik-local.yaml` - Local development (HTTP only)
- `config/traefik-prod.yaml` - Production (HTTPS with Cloudflare DNS challenge)
- `config/conf/` - Directory for dynamic configuration files (routers, middlewares, services)

#### Authelia Configuration
- `authelia/config/configuration-local.yml` - Local development (file-based notifications)
- `authelia/config/configuration-prod.yml` - Production (SMTP email notifications)
- `authelia/config/users_database.yml` - User credentials (gitignored, created by `setup-authelia.sh`)
- `authelia/secrets/` - Cryptographic secrets (gitignored, auto-generated)
- `authelia/data/` - Runtime data (gitignored)

### Managing Authelia Users

To add additional users or change passwords, edit `authelia/data/users_database.yml`:

```bash
# Generate a password hash
docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'your-password-here'

# Edit the users database
nano authelia/data/users_database.yml
```

Add the new user following the existing format, then restart Authelia:

```bash
docker compose restart authelia
```

## Using Traefik with Your Projects

To configure a Docker project to use this Traefik proxy, include the external network in your project's `docker-compose.yml`:

```yaml
networks:
  traefik:
    external: true

services:
  nginx:
    image: shaneturner/nginx:alpine
    init: true
    restart: unless-stopped
    labels:
      # Enable Traefik for this service
      - "traefik.enable=true"
      # Define the domain/URL (use ${DOMAIN:-localhost} for env-based domains)
      - "traefik.http.routers.laravel.rule=Host(`laravel.${DOMAIN:-localhost}`)"
      # Specify the entrypoint (web for HTTP, websecure for HTTPS)
      - "traefik.http.routers.laravel.entrypoints=web"
      # Define which network Traefik should use to find this service
      - "traefik.docker.network=traefik"
      # Specify the port that Traefik should proxy to
      - "traefik.http.services.laravel.loadbalancer.server.port=80"
    volumes:
      - ./src:/var/www/html
    networks:
      - traefik # External network for Traefik
      - default # Internal network for service communication
    depends_on:
      - postgres
      - php

  postgres:
    image: postgres:17
    init: true
    restart: unless-stopped
    ports:
      - "5432"
    environment:
      POSTGRES_DB: laravel
      POSTGRES_USER: laravel
      POSTGRES_PASSWORD: secret
    healthcheck:
      test: ["CMD", "pg_isready", "-q", "-d", "laravel", "-U", "laravel"]
      retries: 3
      timeout: 5s
    volumes:
      - data:/var/lib/postgresql/data
    networks:
      - default # Only needs internal network

  php:
    image: shaneturner/php:8.3
    init: true
    restart: unless-stopped
    depends_on:
      - postgres
    volumes:
      - ./src:/var/www/html
    networks:
      - default # Only needs internal network

volumes:
  data:
```

### Protecting Services with Authelia

To require authentication for a service, add the Authelia middleware to its router labels:

```yaml
services:
  myapp:
    image: myapp:latest
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.myapp.entrypoints=web"
      - "traefik.docker.network=traefik"
      # Add Authelia middleware for authentication
      - "traefik.http.routers.myapp.middlewares=authelia@file"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
    networks:
      - traefik
```

The `authelia@file` middleware is already configured in `config/conf/authelia-middleware.yaml`. Users will be redirected to the Authelia login page before accessing the service.

## Important Notes

- **First-time setup**: You must run `./setup-authelia.sh` before starting Traefik for the first time
- **Setup script order**: 1) Create network, 2) Run `setup-authelia.sh`, 3) Start services, 4) Optionally run `setup-production.sh`
- The nginx service uses both the `traefik` network (for proxy access) and the `default` network (for internal service communication)
- Services that don't need external access (like `postgres` and `php`) only use the `default` network
- For HTTPS/SSL setups, change the entrypoint from `web` to `websecure` in your service labels
- The current setup uses Traefik v3 with file-based configuration
- All containers run as non-root users to prevent permission issues with bind mounts
