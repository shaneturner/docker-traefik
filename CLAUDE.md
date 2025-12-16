# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose setup for Traefik v3 reverse proxy supporting dual environments (local development and production) with file-based configuration and enhanced security via Docker Socket Proxy.

## Architecture

### Security Layer

The project uses a **Docker Socket Proxy** (wollomatic/socket-proxy) to secure access to the Docker API. This is a modern, memory-safe Go-based proxy with regex-based access control. Traefik connects to the Docker daemon through this proxy, which limits access to only read-only operations on containers, networks, and events. This prevents potential attackers from gaining full Docker API access if Traefik is compromised.

**Key security features:**
- Built in Go with zero dependencies (minimal attack surface)
- Regex-based permission rules for fine-grained API access control
- Hostname-based allowlisting (only the `traefik` container can connect)
- Read-only filesystem and dropped capabilities
- Socket watchdog for automatic recovery from Docker daemon issues

### Non-Root User Configuration

Both Traefik and the socket-proxy run as **non-root users** to prevent root-owned files in bind mounts and reduce security risks:

- **Traefik**: Runs as the host user (UID/GID from .env, typically 1000:1000)
- **Socket Proxy**: Runs as user 65534 (nobody) with the Docker group GID for socket access

This ensures:
- All files created in `letsencrypt/` and `logs/` directories are owned by your user account (not root)
- Easy file access and cleanup without sudo
- Reduced attack surface if containers are compromised

The `setup-production.sh` script automatically detects your user ID, group ID, and Docker group ID, then adds them to `.env`.

### Dual Configuration System

The project uses **separate Traefik configuration files** for different environments:

- `config/traefik-local.yaml` - HTTP-only configuration for local development
- `config/traefik-prod.yaml` - HTTPS with Let's Encrypt (Cloudflare DNS challenge) for production

**Key principle**: Only ONE configuration file is mounted at a time via `compose.yaml`. Switch environments by commenting/uncommenting the appropriate volume mount.

### Authelia Authentication

The project integrates **Authelia** for Single Sign-On (SSO) and access control. Authelia protects the Traefik dashboard and can protect any service routed through Traefik.

**Dual configuration system** (same pattern as Traefik):
- `authelia/config/configuration-local.yml` - File-based notifications for local development
- `authelia/config/configuration-prod.yml` - SMTP email notifications for production

**Directory structure:**
- `authelia/config/` - Configuration files (tracked in git except `users_database.yml`)
- `authelia/secrets/` - Cryptographic secrets (gitignored, auto-generated)
- `authelia/data/` - Runtime data and user database (gitignored)

**Initial setup:**
```bash
./setup-authelia.sh
```
This script creates directories, generates secrets, and prompts for an admin user. It's environment-agnostic and only needs to run once.

**Production requirements:**
The `setup-production.sh` script automatically switches Authelia to production mode by:
- Switching from `configuration-local.yml` to `configuration-prod.yml`
- Enabling SMTP environment variables for email notifications
- Substituting template placeholders ({{DOMAIN}}, {{SMTP_HOST}}, etc.) with actual values from `.env`
- Requiring SMTP credentials in `.env` (SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD, SMTP_FROM, ADMIN_EMAIL)

**Key features:**
- Argon2id password hashing
- Session-based authentication with Redis support (optional)
- File-based user database (suitable for small teams)
- 2FA support (TOTP)
- Access control rules per domain/path

### Directory Structure

- `config/conf/` - Dynamic Traefik configuration files (routers, middlewares, services)
- `letsencrypt/` - ACME certificate storage (production only, gitignored)
- `logs/` - Traefik log files (production only, gitignored)

## Commands

### Start Traefik (Local Development)
```bash
docker network create traefik  # First time only
docker compose up -d
```

### Stop Traefik
```bash
docker compose down
```

### View Logs
```bash
docker compose logs -f traefik
```

### Validate Configuration
```bash
docker compose config
```

### Test YAML Syntax
```bash
python3 -c "import yaml; yaml.safe_load(open('config/traefik-local.yaml'))"
python3 -c "import yaml; yaml.safe_load(open('config/traefik-prod.yaml'))"
```

## Environment Switching

### Automated Setup (Recommended)

**Switch to Production:**
```bash
./setup-production.sh
```
This script automatically:
- Switches from `traefik-local.yaml` to `traefik-prod.yaml`
- Switches from `authelia/configuration-local.yml` to `authelia/configuration-prod.yml`
- Enables port 443
- Enables `letsencrypt` and `logs` volume mounts
- Enables Cloudflare DNS environment variables
- Enables Authelia SMTP environment variables
- Creates `.env` from `.env.example` (if not exists)
- **Substitutes template placeholders** in `authelia/config/configuration-prod.yml` with values from `.env`
- **Substitutes template placeholders** in `config/conf/authelia-middleware.yaml` with values from `.env`
- Creates `letsencrypt/acme.json` with 600 permissions
- Creates `logs/` directory
- Verifies `traefik` network exists
- Creates a timestamped backup of `compose.yaml`

After running, edit `.env` to set your actual values:
- `DOMAIN` and `CF_DNS_API_TOKEN` (for Traefik)
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM`, `ADMIN_EMAIL` (for Authelia)

**Switch to Local:**
```bash
./setup-local.sh
```
This script reverts all production changes back to local development configuration (both Traefik and Authelia).

### Manual Configuration

#### Local (Default)
- Uses `config/traefik-local.yaml` (active mount in compose.yaml)
- Port 80 only
- Dashboard at http://traefik.localhost (or http://traefik.${DOMAIN} if DOMAIN is set in .env)

#### Production
Edit `compose.yaml` and:
1. Comment out `traefik-local.yaml` mount, uncomment `traefik-prod.yaml`
2. Comment out `authelia/configuration-local.yml` mount, uncomment `authelia/configuration-prod.yml`
3. Uncomment port 443
4. Uncomment `letsencrypt` and `logs` volume mounts
5. Uncomment `environment` section with `CF_DNS_API_TOKEN`
6. Uncomment Authelia SMTP environment variables
7. Create `.env` file with all required values (see `.env.example`)
8. Create `letsencrypt/acme.json` with `chmod 600` permissions

## Important Constraints

- **Never use command-line flags** in compose.yaml - this setup uses file-based configuration exclusively
- **Never mount both Traefik config files** simultaneously - only one should be active (local OR prod)
- **Never mount both Authelia config files** simultaneously - only one should be active (local OR prod)
- **Never mount the Docker socket directly to Traefik** - always use the socket-proxy service for security
- **Never run containers as root** - UID/GID must be set in `.env` to prevent root-owned files in bind mounts
- **Never commit sensitive Authelia files** - `users_database.yml`, `secrets/`, and `data/` must be gitignored
- Both Traefik config files use `endpoint: "tcp://socket-proxy:2375"` to connect to the Docker Socket Proxy
- Port 8080 is NOT exposed - dashboard access is only via http://traefik.localhost (or configured domain)
- The `traefik` network must exist externally before starting (`docker network create traefik`)
- Production requires `acme.json` to have exactly 600 permissions or Let's Encrypt will fail
- Production config has `debug: false` to reduce information disclosure (local uses `debug: true`)
- The `.env` file must contain UID, GID, DOCKER_GID, and SOCKET_UID values (auto-detected by setup scripts)
- Authelia secrets must have 600 permissions (auto-set by `setup-authelia.sh`)

## Service Integration Pattern

Services using this Traefik instance must:
1. Connect to the external `traefik` network
2. Set `traefik.enable=true` label
3. Define router rule, entrypoint, and service port via labels
4. Maintain separate internal network for inter-service communication

Example labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
  - "traefik.http.routers.myapp.entrypoints=web"
  - "traefik.docker.network=traefik"
  - "traefik.http.services.myapp.loadbalancer.server.port=80"
```
