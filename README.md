# Docker Traefik
Docker Compose Traefik v3 reverse proxy for local development. 

Uses *.localhost for local domains with automatic HTTP routing.

## Quick Start

Create a docker network first:
~~~bash
docker network create traefik
~~~

Then start the Traefik container with Docker Compose:
~~~bash
docker compose up -d
~~~

You can access the Traefik dashboard at: http://localhost:8080/ or http://traefik.localhost

## Configuration Options

**Choose ONE of the following configuration methods:**

### Option 1: Command-Line Configuration (Current Setup)
The current `compose.yaml` uses command-line arguments for basic HTTP setup:
- HTTP routing on port 80
- Traefik dashboard accessible via port 8080 or traefik.localhost
- Automatic service discovery via Docker labels
- Debug logging enabled
- **No config file needed**

### Option 2: Configuration File (For SSL/HTTPS)
For production or SSL-enabled environments, switch to file-based configuration:

1. **Remove or comment out** the `command:` section in `compose.yaml`
2. **Uncomment** the configuration volume mount:
   ~~~yaml
   volumes:
     - /var/run/docker.sock:/var/run/docker.sock
     - ./config/:/etc/traefik/:ro  # Uncomment this line
   ~~~

3. Place your `traefik.yaml` configuration file in the `./config/` directory
4. The included `traefik.yaml` provides HTTPS redirection and Cloudflare DNS challenge for SSL certificates

**Important:** Do not use both command-line configuration AND config file imports simultaneously - choose one approach.

## Using Traefik with Your Projects

To configure a Docker project to use this Traefik proxy, include the external network in your project's `docker-compose.yml`:

~~~yaml
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
      - traefik    # External network for Traefik
      - default    # Internal network for service communication
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
      - default    # Only needs internal network

  php:
    image: shaneturner/php:8.3
    init: true
    restart: unless-stopped
    depends_on:
      - postgres
    volumes:
      - ./src:/var/www/html
    networks:
      - default    # Only needs internal network

volumes:
  data:
~~~

## Important Notes

- The nginx service uses both the `traefik` network (for proxy access) and the `default` network (for internal service communication)
- Services that don't need external access (like `postgres` and `php`) only use the `default` network
- For HTTPS/SSL setups, change the entrypoint from `http` to `https` in your service labels
- The current setup uses Traefik v3 with updated command-line syntax
