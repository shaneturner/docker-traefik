# Docker Traefik
Docker Compose Traefik DNS proxy for local dev. 

Uses *.test for local domains 

Create a docker network first 
```bash
docker network create dev
```

Then start the docker container with Docker Compose
```bash
docker compose up -d
```

To set docker project to use this you need in includ ethe network in the projects docker-compose.yml 

EG:
```YAML
networks:
  dev:
    external: true

services:
  nginx:
    build:
      context: .
      dockerfile: .docker/nginx.dockerfile
    init: true
    labels:
      # REPLACE 'myproject' with the domain prefix you want to use
      #
      # This is enableing treafik to proxy this service
      - "traefik.enable=true"
      # Here we have to define the URL
      - "traefik.http.routers.myproject.rule=Host(`myproject.test`)"
      # Here we are defining wich entrypoint should be used by clients to access this service
      - "traefik.http.routers.myproject.entrypoints=dev"
      # Here we define in wich network treafik can find this service
      - "traefik.docker.network=dev"
      # This is the port that traefik should proxy
      - "traefik.http.services.myproject.loadbalancer.server.port=80"
    volumes:
      - ./src:/var/www/html
    networks:
      - dev
      - default
    depends_on:
      - mysql

  mysql:
    image: mariadb:10.5
    init: true
    ports:
      - 3306:3306
    environment:
      MYSQL_DATABASE: project
      MYSQL_USER: project
      MYSQL_PASSWORD: secret
      MYSQL_ROOT_PASSWORD: secret
    volumes:
      - data:/var/lib/mysql
    networks:
      - default

  volumes:
    data:
```

Note where the nginx server is using both the 'dev' netowrk and the internal 'default' network.
