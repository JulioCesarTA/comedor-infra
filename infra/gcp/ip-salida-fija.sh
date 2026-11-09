#!/usr/bin/env bash
# IP de salida FIJA para GKE (pagos-tickets-service), con Cloud NAT.
#
# Por qué: pagos publica sus eventos en SNS (LocalStack en EKS, puerto 4566), y el grupo de seguridad de AWS solo
# deja entrar a IPs conocidas. Si el nodo de GKE se recrea, cambia su IP pública y los cobros se cuelgan 60 s.
# Con nodos privados + Cloud NAT, todo el tráfico de salida del clúster sale SIEMPRE por la misma IP estática.
#
# Qué hace (idempotente, se puede correr varias veces):
#   1. Reserva la IP estática regional comedor-gke-salida.
#   2. Crea el Cloud Router y el Cloud NAT que usan esa IP (para todos los rangos de la subred: nodos y pods).
#   3. Pasa el pool de nodos a nodos privados (sin IP pública): GKE recrea el nodo y los pods se reprograman.
#      Los balanceadores (LoadBalancer) siguen funcionando igual; las imágenes se bajan por el NAT.
#   4. Comprueba desde el pod de pagos que la salida es la IP del NAT.
#   5. En AWS: autoriza la IP del NAT en el puerto 4566 y quita la regla del nodo anterior.
#
# Requisitos: una cuenta de GCP con permisos de red y de GKE en el proyecto (rol Owner, o Compute Network Admin +
# Kubernetes Engine Admin), activa en gcloud; y las credenciales de AWS en .env.cloud.nuevo (como desplegar-eks.sh).
# Uso (desde comedor-infra, en Git Bash):   bash infra/gcp/ip-salida-fija.sh
set -euo pipefail
export AWS_PAGER=""   # sin MSYS_NO_PATHCONV: en Git Bash rompe el lanzador de gcloud

P=comedor-universitario-514103
REGION=us-central1
ZONA=us-central1-a
CLUSTER=comedor-gke
POOL=default-pool
RED=default
IP_NOMBRE=comedor-gke-salida
ROUTER=comedor-gke-router
NAT=comedor-gke-nat
AWS_R=us-west-2
NODO_ANTERIOR_CIDR="${NODO_ANTERIOR_CIDR:-34.44.248.197/32}"   # regla provisoria que se reemplaza por la del NAT

echo "== 1. IP estática"
gcloud compute addresses describe $IP_NOMBRE --region $REGION --project $P >/dev/null 2>&1 \
  || gcloud compute addresses create $IP_NOMBRE --region $REGION --project $P
IP_NAT=$(gcloud compute addresses describe $IP_NOMBRE --region $REGION --project $P --format="value(address)")
echo "   IP de salida fija: $IP_NAT"

echo "== 2. Cloud Router y Cloud NAT"
gcloud compute routers describe $ROUTER --region $REGION --project $P >/dev/null 2>&1 \
  || gcloud compute routers create $ROUTER --network $RED --region $REGION --project $P
gcloud compute routers nats describe $NAT --router $ROUTER --region $REGION --project $P >/dev/null 2>&1 \
  || gcloud compute routers nats create $NAT --router $ROUTER --region $REGION --project $P \
       --nat-all-subnet-ip-ranges --nat-external-ip-pool=$IP_NOMBRE --enable-logging --log-filter=ERRORS_ONLY

echo "== 3. Nodos privados (GKE recrea el nodo: unos minutos sin pagos)"
PRIVADO=$(gcloud container node-pools describe $POOL --cluster $CLUSTER --zone $ZONA --project $P \
  --format="value(networkConfig.enablePrivateNodes)")
if [ "$PRIVADO" != "True" ]; then
  gcloud container node-pools update $POOL --cluster $CLUSTER --zone $ZONA --project $P --enable-private-nodes
fi
gcloud container clusters get-credentials $CLUSTER --zone $ZONA --project $P >/dev/null
TOKEN=$(gcloud auth print-access-token)
K="kubectl --token=$TOKEN -n comedor"
$K rollout status deploy/postgres-pagos --timeout=600s
$K rollout status deploy/pagos-tickets-service --timeout=600s

echo "== 4. Comprobación de la salida"
POD=$($K get pods -o name | grep pagos-tickets | head -1)
SALIDA=$($K exec ${POD#pod/} -- php -r 'echo @file_get_contents("https://api.ipify.org");')
echo "   el pod de pagos sale por: $SALIDA"
[ "$SALIDA" = "$IP_NAT" ] || { echo "ERROR: la salida no es la IP del NAT"; exit 1; }

echo "== 5. AWS: autorizar la IP del NAT en LocalStack (4566)"
set -a; . ./.env.cloud.nuevo; set +a
SG=$(aws eks describe-cluster --region $AWS_R --name comedor --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 authorize-security-group-ingress --region $AWS_R --group-id $SG --ip-permissions \
  "IpProtocol=tcp,FromPort=4566,ToPort=4566,IpRanges=[{CidrIp=$IP_NAT/32,Description=\"GKE comedor-gke Cloud NAT (IP fija)\"}]" >/dev/null 2>&1 || true
aws ec2 revoke-security-group-ingress --region $AWS_R --group-id $SG --protocol tcp --port 4566 --cidr "$NODO_ANTERIOR_CIDR" >/dev/null 2>&1 || true
$K exec ${POD#pod/} -- php -r '$c=stream_context_create(["http"=>["timeout"=>8]]); echo @file_get_contents("http://44.228.1.64:4566/_localstack/health",false,$c)===false ? "LocalStack: SIN RESPUESTA\n" : "LocalStack: responde\n";'

echo
echo "Listo. IP de salida fija de GKE: $IP_NAT"
echo "Para futuros despliegues de EKS usa PAGOS_IP=$IP_NAT (infra/eksctl/desplegar-eks.sh)."
