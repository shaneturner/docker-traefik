# Docker Traefik

Docker Compose Traefik v3 reverse proxy supporting both local development and production environments with enhanced security via Docker Socket Proxy.

Uses \*.localhost for local domains with automatic HTTP routing, or custom domains in production with HTTPS via Let's Encrypt.

## Quick Start

Create a docker network first:

```bash
docker network create traefik
```

Then start the Traefik container with Docker Compose:

```bash
docker compose up -d
```

You can access the Traefik dashboard at: http://traefik.localhost

## Configuration

This setup uses **file-based configuration** with separate config files for local development and production environments.

### Security

This setup includes a **Docker Socket Proxy** ([wollomatic/socket-proxy](https://github.com/wollomatic/socket-proxy)) for enhanced security. This modern, memory-safe Go-based proxy sits between Traefik and the Docker socket, using regex-based access control to limit Traefik's access to only the Docker API endpoints it needs (containers, networks, and events), with all write operations disabled. This significantly reduces the attack surface if Traefik is compromised.

**Key security features:**
- Built in Go with zero dependencies (minimal attack surface)
- Regex-based permission rules for fine-grained API access control
- Hostname-based allowlisting (only the `traefik` container can connect)
- Read-only filesystem and dropped capabilities
- Socket watchdog for automatic recovery from Docker daemon issues

### Local Development (Default)

The default configuration uses `config/traefik-local.yaml`:

- HTTP only on port 80
- Traefik dashboard accessible at http://traefik.localhost
- Debug logging enabled
- No SSL/HTTPS

**No changes needed** - just run `docker compose up -d`

### Production Deployment

#### Automated Setup (Recommended)

Run the production setup script:

```bash
./setup-production.sh
```

This automatically:
- Switches from `traefik-local.yaml` to `traefik-prod.yaml`
- Enables port 443 for HTTPS
- Enables `letsencrypt` and `logs` volume mounts
- Enables Cloudflare DNS environment variables
- Creates `.env` from `.env.example` (if not exists)
- Creates `letsencrypt/acme.json` with 600 permissions
- Creates `logs/` directory
- Verifies `traefik` network exists
- Creates a timestamped backup of `compose.yaml`

After running the script:

1. **Edit `.env`** and set your actual values:
   ```bash
   DOMAIN=example.com
   CF_DNS_API_TOKEN=your_cloudflare_api_token_here
   ```

2. **Start Traefik**:
   ```bash
   docker compose up -d
   ```

#### Switch Back to Local

To revert to local development configuration:

```bash
./setup-local.sh
docker compose up -d
```

#### Manual Setup

If you prefer to configure manually, see the detailed steps in `CLAUDE.md`.

### Configuration Files

- `config/traefik-local.yaml` - Local development (HTTP only)
- `config/traefik-prod.yaml` - Production (HTTPS with Cloudflare DNS challenge)
- `config/conf/` - Directory for dynamic configuration files (routers, middlewares, services)

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

## Important Notes

- The nginx service uses both the `traefik` network (for proxy access) and the `default` network (for internal service communication)
- Services that don't need external access (like `postgres` and `php`) only use the `default` network
- For HTTPS/SSL setups, change the entrypoint from `web` to `websecure` in your service labels
- The current setup uses Traefik v3 with file-based configuration
