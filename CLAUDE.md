# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker Compose setup for Traefik v3 reverse proxy supporting dual environments (local development and production) with file-based configuration.

## Architecture

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

### Local (Default)
- Uses `config/traefik-local.yaml` (active mount in compose.yaml)
- Port 80 only
- Dashboard at http://traefik.localhost

### Production
Edit `compose.yaml` and:
1. Comment out `traefik-local.yaml` mount, uncomment `traefik-prod.yaml`
2. Uncomment port 443
3. Uncomment `letsencrypt` and `logs` volume mounts
4. Uncomment `environment` section with `CF_DNS_API_TOKEN`
5. Create `.env` file with Cloudflare API token
6. Create `letsencrypt/acme.json` with `chmod 600` permissions

## Important Constraints

- **Never use command-line flags** in compose.yaml - this setup uses file-based configuration exclusively
- **Never mount both config files** simultaneously - only one should be active
- Port 8080 is NOT exposed - dashboard access is only via http://traefik.localhost
- The `traefik` network must exist externally before starting (`docker network create traefik`)
- Production requires `acme.json` to have exactly 600 permissions or Let's Encrypt will fail

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
