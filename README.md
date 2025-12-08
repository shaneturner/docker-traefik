# Docker Traefik

Docker Compose Traefik v3 reverse proxy for local development.

Uses \*.localhost for local domains with automatic HTTP routing.

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

### Local Development (Default)

The default configuration uses `config/traefik-local.yaml`:

- HTTP only on port 80
- Traefik dashboard accessible at http://traefik.localhost
- Debug logging enabled
- No SSL/HTTPS

**No changes needed** - just run `docker compose up -d`

### Production Deployment

To switch to production configuration with HTTPS and Let's Encrypt:

1. **Update `compose.yaml`** - Swap the configuration file mounts:

   ```yaml
   volumes:
     - /var/run/docker.sock:/var/run/docker.sock
     # - ./config/traefik-local.yaml:/etc/traefik/traefik.yaml:ro  # Comment out local
     - ./config/traefik-prod.yaml:/etc/traefik/traefik.yaml:ro # Uncomment production
     - ./config/conf/:/etc/traefik/conf/:ro
     - ./letsencrypt:/letsencrypt # Uncomment for certificate storage
     - ./logs:/var/log/traefik # Uncomment for logging
   ```

2. **Enable port 443**:

   ```yaml
   ports:
     - "80:80"
     - "443:443" # Uncomment this line
   ```

3. **Set up Cloudflare DNS API Token**:

   Create a `.env` file in the project root:

   ```bash
   CF_DNS_API_TOKEN=your_cloudflare_api_token_here
   ```

   Then uncomment the environment section in `compose.yaml`:

   ```yaml
   environment:
     - CF_DNS_API_TOKEN=${CF_DNS_API_TOKEN}
   ```

4. **Create `acme.json` with proper permissions**:

   ```bash
   touch letsencrypt/acme.json
   chmod 600 letsencrypt/acme.json
   ```

5. **Restart Traefik**:
   ```bash
   docker compose down
   docker compose up -d
   ```

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
      # Define the domain/URL
      - "traefik.http.routers.laravel.rule=Host(`laravel.localhost`)"
      # Specify the entrypoint (http for basic setup)
      - "traefik.http.routers.laravel.entrypoints=http"
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
- For HTTPS/SSL setups, change the entrypoint from `http` to `https` in your service labels
- The current setup uses Traefik v3 with updated command-line syntax
