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
- Enables port 443
- Enables `letsencrypt` and `logs` volume mounts
- Enables Cloudflare DNS environment variables
- Creates `.env` from `.env.example` (if not exists)
- Creates `letsencrypt/acme.json` with 600 permissions
- Creates `logs/` directory
- Verifies `traefik` network exists
- Creates a timestamped backup of `compose.yaml`

After running, edit `.env` to set your actual `DOMAIN` and `CF_DNS_API_TOKEN` values.

**Switch to Local:**
```bash
./setup-local.sh
```
This script reverts all production changes back to local development configuration.

### Manual Configuration

#### Local (Default)
- Uses `config/traefik-local.yaml` (active mount in compose.yaml)
- Port 80 only
- Dashboard at http://traefik.localhost (or http://traefik.${DOMAIN} if DOMAIN is set in .env)

#### Production
Edit `compose.yaml` and:
1. Comment out `traefik-local.yaml` mount, uncomment `traefik-prod.yaml`
2. Uncomment port 443
3. Uncomment `letsencrypt` and `logs` volume mounts
4. Uncomment `environment` section with `CF_DNS_API_TOKEN`
5. Create `.env` file with Cloudflare API token and DOMAIN
6. Create `letsencrypt/acme.json` with `chmod 600` permissions

## Important Constraints

- **Never use command-line flags** in compose.yaml - this setup uses file-based configuration exclusively
- **Never mount both config files** simultaneously - only one should be active
- **Never mount the Docker socket directly to Traefik** - always use the socket-proxy service for security
- **Never run containers as root** - UID/GID must be set in `.env` to prevent root-owned files in bind mounts
- Both config files use `endpoint: "tcp://socket-proxy:2375"` to connect to the Docker Socket Proxy
- Port 8080 is NOT exposed - dashboard access is only via http://traefik.localhost (or configured domain)
- The `traefik` network must exist externally before starting (`docker network create traefik`)
- Production requires `acme.json` to have exactly 600 permissions or Let's Encrypt will fail
- Production config has `debug: false` to reduce information disclosure (local uses `debug: true`)
- The `.env` file must contain UID, GID, DOCKER_GID, and SOCKET_UID values (auto-detected by setup scripts)

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
