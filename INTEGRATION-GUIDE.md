# Authelia Integration Guide

This guide explains how to integrate Authelia authentication with services running in other Docker Compose projects on the same server.

## Overview

The `authelia-auth@file` middleware is **globally available** to all services on this server, regardless of which Docker Compose file they're defined in. The `@file` suffix tells Traefik to use the middleware from the file provider (not Docker labels), making it accessible to any service that connects to the `traefik` network.

## Quick Start

To protect any service with Authelia authentication:

1. **Connect service to Traefik network**
2. **Add middleware label to service**
3. **Configure access control in Authelia**
4. **Restart Authelia**

## Step-by-Step Instructions

### Step 1: Connect Service to Traefik Network

In your service's `docker-compose.yml` (e.g., `/home/user/n8n/docker-compose.yml`):

```yaml
networks:
  traefik:
    external: true  # Reference the external traefik network
  default:          # Internal network for service-to-service communication

services:
  n8n:
    image: n8nio/n8n:latest
    networks:
      - traefik   # Connect to Traefik for external access
      - default   # Internal network for database, etc.
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.n8n.entrypoints=web"
      - "traefik.http.routers.n8n.middlewares=authelia-auth@file"  # ADD THIS LINE
      # For HTTPS (production):
      - "traefik.http.routers.n8n-secure.rule=Host(`n8n.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.n8n-secure.entrypoints=websecure"
      - "traefik.http.routers.n8n-secure.tls=true"
      - "traefik.http.routers.n8n-secure.tls.certresolver=cloudflare"
      - "traefik.http.routers.n8n-secure.middlewares=authelia-auth@file"  # ADD THIS LINE
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
```

**Key Points:**
- `external: true` on the traefik network - it already exists
- `traefik.docker.network=traefik` - tells Traefik which network to use
- `middlewares=authelia-auth@file` - the `@file` suffix is CRITICAL
- Both HTTP and HTTPS routers need the middleware

### Step 2: Configure Access Control in Authelia

Edit `/home/sean/Code/personal/traefik/authelia/config/configuration-local.yml` (or `-prod.yml` for production):

```yaml
access_control:
  default_policy: deny
  rules:
    # Existing rules...

    # Add your new service
    - domain: n8n.localhost              # or n8n.${DOMAIN} for production
      policy: two_factor                 # Require password + TOTP
      subject:
        - "group:admins"                 # Only admins can access
        - "group:dev"                    # Or developers

    # Alternative: One-factor for less sensitive services
    # - domain: docs.localhost
    #   policy: one_factor               # Password only, no TOTP
    #   subject:
    #     - "group:viewers"
```

**Policy Options:**
- `bypass` - No authentication required (public)
- `one_factor` - Password only
- `two_factor` - Password + TOTP/WebAuthn (recommended)
- `deny` - Explicitly deny access

**Subject Options:**
- `"group:admins"` - Match users in the admins group
- `"user:john"` - Match specific user
- Omit subject to allow all authenticated users

### Step 3: Restart Authelia

```bash
cd /home/sean/Code/personal/traefik
docker compose restart authelia
```

Changes to `access_control` rules require an Authelia restart.

### Step 4: Test Access

1. Navigate to `http://n8n.localhost` (or your configured domain)
2. You should be redirected to Authelia login
3. Log in with your credentials
4. Enter TOTP code
5. You'll be redirected back to n8n

## Complete Examples

### Example 1: n8n Workflow Automation

**File:** `/home/user/n8n/docker-compose.yml`

```yaml
networks:
  traefik:
    external: true
  default:

services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: unless-stopped
    networks:
      - traefik
      - default
    environment:
      - N8N_HOST=n8n.${DOMAIN:-localhost}
      - WEBHOOK_URL=https://n8n.${DOMAIN:-localhost}/
    volumes:
      - ./data:/home/node/.n8n
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.n8n.rule=Host(`n8n.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.n8n.entrypoints=web"
      - "traefik.http.routers.n8n.middlewares=authelia-auth@file"
      - "traefik.http.routers.n8n-secure.rule=Host(`n8n.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.n8n-secure.entrypoints=websecure"
      - "traefik.http.routers.n8n-secure.tls=true"
      - "traefik.http.routers.n8n-secure.tls.certresolver=cloudflare"
      - "traefik.http.routers.n8n-secure.middlewares=authelia-auth@file"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
```

**Authelia access control:**
```yaml
- domain: n8n.${DOMAIN:-localhost}
  policy: two_factor
  subject:
    - "group:admins"
```

### Example 2: Grafana Monitoring Dashboard

**File:** `/home/user/monitoring/docker-compose.yml`

```yaml
networks:
  traefik:
    external: true
  monitoring:

services:
  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    networks:
      - traefik
      - monitoring
    volumes:
      - grafana-data:/var/lib/grafana
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.grafana.rule=Host(`grafana.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.grafana.entrypoints=web"
      - "traefik.http.routers.grafana.middlewares=authelia-auth@file"
      - "traefik.http.routers.grafana-secure.rule=Host(`grafana.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.grafana-secure.entrypoints=websecure"
      - "traefik.http.routers.grafana-secure.tls=true"
      - "traefik.http.routers.grafana-secure.tls.certresolver=cloudflare"
      - "traefik.http.routers.grafana-secure.middlewares=authelia-auth@file"
      - "traefik.http.services.grafana.loadbalancer.server.port=3000"

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    networks:
      - monitoring  # Internal only, not exposed to internet
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - prometheus-data:/prometheus

volumes:
  grafana-data:
  prometheus-data:
```

**Authelia access control (different policies for different groups):**
```yaml
# Admins get full access with 2FA
- domain: grafana.${DOMAIN:-localhost}
  policy: two_factor
  subject:
    - "group:admins"

# Developers get read-only with 1FA
- domain: grafana.${DOMAIN:-localhost}
  policy: one_factor
  subject:
    - "group:dev"
```

### Example 3: Multiple Services in One Compose File

**File:** `/home/user/home-apps/docker-compose.yml`

```yaml
networks:
  traefik:
    external: true
  default:

services:
  # Service 1: Protected with 2FA
  portainer:
    image: portainer/portainer-ce:latest
    restart: unless-stopped
    networks:
      - traefik
      - default
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer-data:/data
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.portainer.rule=Host(`portainer.${DOMAIN:-localhost}`)"
      - "traefik.http.routers.portainer.middlewares=authelia-auth@file"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"

  # Service 2: Public (no auth)
  blog:
    image: ghost:latest
    restart: unless-stopped
    networks:
      - traefik
      - default
    environment:
      url: https://blog.${DOMAIN:-localhost}
    volumes:
      - ghost-data:/var/lib/ghost/content
    labels:
      - "traefik.enable=true"
      - "traefik.docker.network=traefik"
      - "traefik.http.routers.blog.rule=Host(`blog.${DOMAIN:-localhost}`)"
      # NOTE: No middleware = public access
      - "traefik.http.services.blog.loadbalancer.server.port=2368"

volumes:
  portainer-data:
  ghost-data:
```

**Authelia access control:**
```yaml
# Portainer - only admins
- domain: portainer.${DOMAIN:-localhost}
  policy: two_factor
  subject:
    - "group:admins"

# Blog - public, no rule needed (default_policy: deny won't affect it because no middleware is applied)
```

## Advanced Patterns

### Pattern 1: Path-Based Access Control

Protect only specific paths:

```yaml
labels:
  # Protect admin panel
  - "traefik.http.routers.app-admin.rule=Host(`app.localhost`) && PathPrefix(`/admin`)"
  - "traefik.http.routers.app-admin.middlewares=authelia-auth@file"
  - "traefik.http.routers.app-admin.priority=100"  # Higher priority

  # Allow public access to main app
  - "traefik.http.routers.app-public.rule=Host(`app.localhost`)"
  - "traefik.http.routers.app-public.priority=1"  # Lower priority
```

### Pattern 2: Different Auth Levels

```yaml
# Critical service - require 2FA (uses full authelia-auth)
- "traefik.http.routers.database-admin.middlewares=authelia-auth@file"

# Less critical - only require password (uses authelia-basic)
- "traefik.http.routers.docs.middlewares=authelia-basic@file"
```

### Pattern 3: Bypass Auth for Specific IPs

In Authelia `configuration.yml`:

```yaml
access_control:
  rules:
    # Allow office network without auth
    - domain: internal.example.com
      policy: bypass
      networks:
        - 192.168.1.0/24

    # Everyone else needs 2FA
    - domain: internal.example.com
      policy: two_factor
```

## Troubleshooting

### Issue: "Middleware authelia@docker not found"

**Solution:** You used `authelia@docker` instead of `authelia-auth@file`. The `@file` suffix is critical.

### Issue: Service can't reach Authelia

**Solution:** Ensure the `traefik` network exists:
```bash
docker network create traefik
```

### Issue: Access control not working

**Solutions:**
1. Restart Authelia after changing access_control rules
2. Check domain matches exactly (including `${DOMAIN}` substitution)
3. Verify user is in the correct group in `users_database.yml`

### Issue: Infinite redirect loop

**Solution:** Ensure Authelia's `/api/verify` endpoint has `policy: bypass` in access_control:

```yaml
access_control:
  rules:
    - domain: authelia.localhost
      policy: bypass
      resources:
        - "^/api/verify.*$"
        - "^/api/authz/.*$"
```

## User Management

### Adding Users

1. **Generate password hash:**
   ```bash
   docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2 --password 'yourpassword'
   ```

2. **Edit users_database.yml:**
   ```yaml
   users:
     admin:
       # ... existing admin ...

     newuser:
       displayname: "New User"
       password: "$argon2id$v=19$m=65536,t=3,p=4$<HASH>"
       email: newuser@example.com
       groups:
         - dev
   ```

3. **Restart Authelia:**
   ```bash
   cd /home/sean/Code/personal/traefik
   docker compose restart authelia
   ```

### Managing Groups

Groups are defined in `users_database.yml` under each user and referenced in access control rules:

```yaml
# In users_database.yml
users:
  john:
    groups:
      - admins
      - dev

# In configuration.yml access_control
- domain: admin.localhost
  policy: two_factor
  subject:
    - "group:admins"  # Only users in the admins group
```

## Security Best Practices

1. **Use two_factor policy for sensitive services**
2. **Limit access with subject rules (groups/users)**
3. **Keep default_policy set to deny**
4. **Regularly review access control rules**
5. **Use strong passwords (enforced by Argon2id)**
6. **Enable TOTP or WebAuthn for all users**
7. **Monitor Authelia logs for failed authentication attempts**

## For Future Agents

When asked to integrate a service with Authelia:

1. **Check if traefik network exists** - it should
2. **Add labels to the service** - use the patterns above
3. **Add access control rule in Authelia config** - match the domain and set appropriate policy
4. **Restart Authelia** - required for config changes
5. **Test the integration** - verify redirect and authentication work

**Critical syntax:**
- Middleware MUST use `@file` suffix: `authelia-auth@file`
- Domain MUST match exactly (including `${DOMAIN}` variable)
- Access control bypass MUST exist for `/api/verify`
