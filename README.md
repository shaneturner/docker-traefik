# Docker Traefik
Docker Compose Traefik DNS proxy for local dev. 

Uses *.localhost for local domains 

Create a docker network first 
```bash
docker network create dev
```

Then start the docker container with Docker Compose
```bash
docker compose up -d
```

You can access the Traefic dashboard: http://localhost:8080/ or http://traefik.localhost

To set docker project to use this you need in include the network in the projects docker-compose.yml 

EG:
```YAML
networks:
  dev:
    external: true

services:
  nginx:
    image: shaneturner/nginx:alpine
    init: true
    restart: unless-stopped
    labels:
      # This is enableing treafik to proxy this service
      - "traefik.enable=true"
      # Here we have to define the URL
      - "traefik.http.routers.laravel.rule=Host(`laravel.localhost`)"
      # Here we are defining wich entrypoint should be used by clients to access this service
      - "traefik.http.routers.laravel.entrypoints=dev"
      # Here we define in wich network treafik can find this service
      - "traefik.docker.network=dev"
      # This is the port that traefik should proxy
      - "traefik.http.services.laravel.loadbalancer.server.port=80"
    volumes:
      - ./src:/var/www/html
    networks:
      - dev
      - default
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
      - default

  php:
    image: shaneturner/php:8.3
    init: true
    restart: unless-stopped
    depends_on:
      - postgres
    volumes:
      - ./src:/var/www/html
    networks:
      - default
```

Note where the nginx server is using both the 'dev' network and the internal 'default' network.
