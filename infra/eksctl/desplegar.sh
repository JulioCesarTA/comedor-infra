#!/usr/bin/env bash
# Crea los secretos y ConfigMaps en el clúster y aplica los manifiestos.
# Requiere: kubectl apuntando al clúster, .env, .env.secrets, .env.cloud (Mongo Atlas), .env.cloud.nuevo (RDS) y
# .comedor-app.keys.tmp (claves del usuario IAM comedor-app) en la raíz del proyecto.
# Uso: bash infra/eksctl/desplegar.sh <realm.json>
set -euo pipefail
REALM=${1:?falta el realm.json generado con crear_realm.py}
leer() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }

RDS_HOST=$(leer .env.cloud.nuevo RDS_HOST); RDS_PASSWORD=$(leer .env.cloud.nuevo RDS_PASSWORD)
read -r APP_ID APP_SECRET < .comedor-app.keys.tmp
APP_KEY=$(grep -E "^\s+APP_KEY:" docker-compose.yml | head -1 | sed 's/.*APP_KEY: *//' | tr -d '"')

kubectl create namespace comedor --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create secret generic aws-app --from-literal=id="$APP_ID" --from-literal=secret="$APP_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create secret generic comedor \
  --from-literal=mongo-uri="$(leer .env.cloud MONGO_ATLAS_URI)" \
  --from-literal=rds-host="$RDS_HOST" --from-literal=rds-password="$RDS_PASSWORD" \
  --from-literal=url-comensales="postgres://postgres:$RDS_PASSWORD@$RDS_HOST:5432/comensales_reservas" \
  --from-literal=url-cqrs="postgresql://postgres:$RDS_PASSWORD@$RDS_HOST:5432/cqrs_read" \
  --from-literal=url-keycloak-jdbc="jdbc:postgresql://$RDS_HOST:5432/keycloak" \
  --from-literal=app-key="$APP_KEY" \
  --from-literal=stripe="$(leer .env.secrets STRIPE_SECRET_KEY)" \
  --from-literal=telegram="$(leer .env.secrets TELEGRAM_BOT_TOKEN)" \
  --from-literal=kc-admin="$(leer .env KEYCLOAK_ADMIN)" --from-literal=kc-admin-password="$(leer .env KEYCLOAK_ADMIN_PASSWORD)" \
  --from-literal=n8n-user="$(leer .env N8N_BASIC_AUTH_USER)" --from-literal=n8n-password="$(leer .env N8N_BASIC_AUTH_PASSWORD)" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create configmap realm --from-file=comedor-realm.json="$REALM" --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create configmap flujos-n8n --from-file=automation/n8n/flows --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f infra/k8s/eks/comedor.yaml
