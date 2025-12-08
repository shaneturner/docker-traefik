# Traefik Integration Guide

Instructions for integrating Docker Compose projects with the running Traefik reverse proxy.

## Prerequisites

- Traefik container is running
- External `traefik` network exists

## Basic Integration

### 1. Add External Network

```yaml
networks:
  traefik:
    external: true
```

### 2. Configure Service

Services requiring external access need:
- Connection to both `traefik` (external) and `default` (internal) networks
- Traefik labels for routing configuration

```yaml
services:
  web:
    image: nginx:alpine
    networks:
      - traefik   # For proxy access
      - default   # For internal service communication
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.myapp.rule=Host(`myapp.localhost`)"
      - "traefik.http.routers.myapp.entrypoints=web"
      - "traefik.docker.network=traefik"
      - "traefik.http.services.myapp.loadbalancer.server.port=80"
```

### 3. Internal Services

Backend services (databases, caches, workers) should **only** use the `default` network:

```yaml
services:
  postgres:
    image: postgres:17
    networks:
      - default  # No traefik network needed
```

## Required Labels

| Label | Purpose | Example |
|-------|---------|---------|
| `traefik.enable` | Enable Traefik routing | `"true"` |
| `traefik.http.routers.{name}.rule` | Define routing rule | `Host(\`app.localhost\`)` |
| `traefik.http.routers.{name}.entrypoints` | Specify entrypoint | `web` (HTTP) or `websecure` (HTTPS) |
| `traefik.docker.network` | Network for Traefik to use | `traefik` |
| `traefik.http.services.{name}.loadbalancer.server.port` | Container port | `80`, `3000`, `8080`, etc. |

## Common Patterns

### Multiple Domains

```yaml
labels:
  - "traefik.http.routers.app.rule=Host(`app.localhost`) || Host(`www.app.localhost`)"
```

### Path-Based Routing

```yaml
labels:
  - "traefik.http.routers.api.rule=Host(`myapp.localhost`) && PathPrefix(`/api`)"
```

### Non-Standard Port

```yaml
labels:
  - "traefik.http.services.app.loadbalancer.server.port=3000"
```

## Production (HTTPS)

Change entrypoint and add certificate resolver:

```yaml
labels:
  - "traefik.http.routers.myapp.entrypoints=websecure"
  - "traefik.http.routers.myapp.tls.certresolver=cloudflare"
```

## Troubleshooting

**Service not accessible:**
1. Verify service is on `traefik` network: `docker inspect <container> | grep traefik`
2. Check Traefik dashboard: http://traefik.localhost
3. Verify `traefik.enable=true` label exists
4. Confirm `traefik.docker.network=traefik` is set
5. Check container port matches loadbalancer port

**Wrong network error:**
- Service must be on the same network Traefik is monitoring (`traefik`)
- Use `traefik.docker.network=traefik` label if service is on multiple networks
