#!/usr/bin/env bash
# Despliega en las 4 EC2 (menu -> comensales -> pagos -> stack). Requiere crear-ec2.sh, las instancias internas y las imágenes ya subidas a ECR.
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/ec2/desplegar-ec2.sh [rol ...]     (sin argumentos despliega los 4)
set -euo pipefail
export MSYS_NO_PATHCONV=1 AWS_PAGER=""
R=us-west-2
ECR=$(aws sts get-caller-identity --query Account --output text).dkr.ecr.$R.amazonaws.com
ssh_() { ssh -i respaldo/ec2-comedor.pem -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=30 ubuntu@$1 "${@:2}"; }

python infra/ec2/realm.py "$EC2_HOST" deploy/ec2/realm/comedor-realm.json
KC_PASS=$(grep -s ^KEYCLOAK_ADMIN_PASSWORD= respaldo/env.ec2 | cut -d= -f2- || true)
N8N_PASS=$(grep -s ^N8N_BASIC_AUTH_PASSWORD= respaldo/env.ec2 | cut -d= -f2- || true)
{
  echo "HOST=$EC2_HOST"
  echo "ECR=ghcr.io/juliocesarta"
  echo "IP_STACK=$WEB_PRIV"
  echo "IP_MENU=$AWS_BOX_PRIV"
  echo "IP_COMENSALES=$AZURE_PRIV"
  echo "IP_PAGOS=$GCP_PRIV"
  echo "KEYCLOAK_ADMIN_PASSWORD=${KC_PASS:-$(python -c 'import secrets;print(secrets.token_urlsafe(12))')}"
  echo "N8N_BASIC_AUTH_PASSWORD=${N8N_PASS:-$(python -c 'import secrets;print(secrets.token_urlsafe(12))')}"
} > respaldo/env.ec2.nuevo && mv respaldo/env.ec2.nuevo respaldo/env.ec2

ARCHIVOS="docker-compose.yml docker-compose.ec2.yml .env .env.secrets auth eventbus/infra automation/n8n/flows deploy/ec2/realm infra/ec2/remoto.sh infra/ec2/cargar_dynamodb.py"
RESPALDOS=$(ls respaldo/comensales_reservas.sql respaldo/pagos_tickets.sql respaldo/cqrs_read.sql respaldo/dynamodb-*.json respaldo/mongo.archive.gz 2>/dev/null || true)

desplegar() {  # rol ip
  echo "################ $1 ($2)"
  until ssh_ $2 'test -f /var/lib/cloud/instance/listo-comedor' 2>/dev/null; do sleep 10; done
  tar czf - $ARCHIVOS $RESPALDOS | ssh_ $2 'rm -rf ~/comedor && mkdir -p ~/comedor && tar xzf - -C ~/comedor'
  scp -i respaldo/ec2-comedor.pem respaldo/env.ec2 ubuntu@$2:comedor/.env.ec2 >/dev/null
  gh auth token | ssh_ $2 "docker login ghcr.io -u JulioCesarTA --password-stdin" 2>&1 | tail -1 || true   # las imágenes están en GHCR
  ssh_ $2 "bash ~/comedor/infra/ec2/remoto.sh $1"
}
ROLES=${*:-menu comensales pagos stack}
for r in $ROLES; do
  case $r in
    menu) desplegar menu $AWS_BOX_IP;;
    comensales) desplegar comensales $AZURE_IP;;
    pagos) desplegar pagos $GCP_IP;;
    stack) desplegar stack $EC2_IP;;
  esac
done
echo "listo: https://$EC2_HOST"
