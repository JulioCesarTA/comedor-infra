#!/usr/bin/env bash
# Se ejecuta EN cada EC2 (lo lanza desplegar-ec2.sh). Uso: remoto.sh <menu|comensales|pagos|stack>
set -euo pipefail
ROL=${1:?falta el rol: menu | comensales | pagos | stack}
cd ~/comedor
set -a; . ./.env.ec2; . ./.env; set +a
F="--env-file .env --env-file .env.secrets --env-file .env.ec2 -f docker-compose.yml -f docker-compose.ec2.yml"

esperar() { until [ "$(docker inspect -f '{{.State.Health.Status}}' $1 2>/dev/null)" = "healthy" ]; do sleep 3; done; }
cargar_sql() {  # contenedor usuario base contraseña  (recrea el esquema y carga el respaldo)
  docker exec -e PGPASSWORD="$4" $1 psql -q -U $2 -d $3 -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;" >/dev/null 2>&1
  docker exec -i -e PGPASSWORD="$4" $1 psql -q -U $2 -d $3 < respaldo/$3.sql >/dev/null 2>&1 || true
  echo "   $3: $(docker exec -e PGPASSWORD="$4" $1 psql -U $2 -d $3 -Atc "select coalesce(string_agg(relname||'='||n_live_tup, ' '),'sin tablas') from pg_stat_user_tables")"
}

docker compose $F down --remove-orphans >/dev/null 2>&1 || true

if [ "$ROL" = "menu" ]; then
  echo "== [ec2-menu-inv] menu-inventario (+mongo)"
  docker compose $F pull --quiet mongo menu-inventario-service
  docker compose $F up -d --no-deps mongo
  esperar comedor-mongo
  if [ -f respaldo/mongo.archive.gz ]; then
    docker exec -i comedor-mongo mongorestore --archive --gzip --drop -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin < respaldo/mongo.archive.gz 2>&1 | tail -1
  fi
  docker compose $F up -d --no-deps menu-inventario-service
fi

if [ "$ROL" = "comensales" ]; then
  echo "== [ec2-comensales] comensales-reservas (+postgres propio)"
  docker compose $F pull --quiet postgres-comensales comensales-reservas-service
  docker compose $F up -d --no-deps postgres-comensales
  esperar comedor-postgres-comensales
  cargar_sql comedor-postgres-comensales "$POSTGRES_COMENSALES_USER" "$POSTGRES_COMENSALES_DB" "$POSTGRES_COMENSALES_PASSWORD"
  docker compose $F up -d --no-deps comensales-reservas-service
fi

if [ "$ROL" = "pagos" ]; then
  echo "== [ec2-pagos] pagos-tickets (+postgres propio)"
  docker compose $F pull --quiet postgres-pagos pagos-tickets-service
  docker compose $F up -d --no-deps postgres-pagos
  esperar comedor-postgres-pagos
  cargar_sql comedor-postgres-pagos "$POSTGRES_PAGOS_USER" "$POSTGRES_PAGOS_DB" "$POSTGRES_PAGOS_PASSWORD"
  docker compose $F up -d --no-deps pagos-tickets-service
fi

if [ "$ROL" = "stack" ]; then
  echo "== [web] nginx y certificado para $HOST"
  sudo mkdir -p /var/www/html
  sudo rm -f /etc/nginx/sites-enabled/default
  HTTP80="server { listen 80; server_name $HOST; location /.well-known/acme-challenge/ { root /var/www/html; } location / { return 301 https://\$host\$request_uri; } }"
  echo "$HTTP80" | sudo tee /etc/nginx/sites-available/comedor >/dev/null
  sudo ln -sf /etc/nginx/sites-available/comedor /etc/nginx/sites-enabled/comedor
  sudo nginx -t && sudo systemctl reload nginx
  if [ ! -f /etc/letsencrypt/live/$HOST/fullchain.pem ]; then
    sudo certbot certonly --webroot -w /var/www/html -d $HOST --non-interactive --agree-tos --register-unsafely-without-email
  fi
  printf '#!/bin/sh\nsystemctl reload nginx\n' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/recargar-nginx.sh >/dev/null
  sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/recargar-nginx.sh
  printf "map \$http_upgrade \$connection_upgrade { default upgrade; '' close; }\n" | sudo tee /etc/nginx/conf.d/websocket.conf >/dev/null
  bloque() {  # puerto público, destino host:puerto
    cat <<B
server {
  listen $1 ssl;
  server_name $HOST;
  ssl_certificate /etc/letsencrypt/live/$HOST/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$HOST/privkey.pem;
  ssl_protocols TLSv1.2 TLSv1.3;
  client_max_body_size 25m;
  location / {
    proxy_pass http://$2;
    proxy_http_version 1.1;
    proxy_set_header Host \$http_host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-Host \$http_host;
    proxy_set_header X-Forwarded-Port \$server_port;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;
    proxy_read_timeout 120s;
  }
}
B
  }
  {
    echo "$HTTP80"
    bloque 443 127.0.0.1:13000; bloque 3001 127.0.0.1:13001; bloque 3002 127.0.0.1:13002; bloque 3003 127.0.0.1:13003
    bloque 8080 127.0.0.1:18080; bloque 8085 127.0.0.1:18085; bloque 5678 127.0.0.1:15678
  } | sudo tee /etc/nginx/sites-available/comedor >/dev/null
  sudo nginx -t && sudo systemctl reload nginx
  echo "== [stack] infraestructura de soporte (cqrs, dynamodb, localstack) e ia-ml"
  docker compose $F pull --quiet postgres-cqrs dynamodb-local localstack ia-ml-service
  docker compose $F up -d --no-deps postgres-cqrs dynamodb-local
  esperar comedor-postgres-cqrs
  cargar_sql comedor-postgres-cqrs "$POSTGRES_CQRS_USER" "$POSTGRES_CQRS_DB" "$POSTGRES_CQRS_PASSWORD"
  chmod +x eventbus/infra/init-localstack.sh
  docker compose $F up -d --no-deps localstack ia-ml-service
  sleep 25
  for t in sagas idempotency_keys; do docker cp respaldo/dynamodb-$t.json comedor-ia-ml:/tmp/dynamodb-$t.json; done
  docker cp infra/ec2/cargar_dynamodb.py comedor-ia-ml:/tmp/cargar_dynamodb.py
  docker exec comedor-ia-ml python /tmp/cargar_dynamodb.py
  echo "== [stack] keycloak, gateways, n8n y frontends"
  SERV="keycloak api-gateway graphql-gateway n8n shell backoffice-gestion portal-estudiante inteligencia-negocio"
  docker compose $F pull --quiet $SERV
  docker compose $F up -d --no-deps $SERV
fi
docker ps --format 'table {{.Names}}\t{{.Status}}' | head -20
