#!/usr/bin/env bash
# Despliega la parte AWS del sistema en el clúster EKS "comedor" (ya creado con eksctl y con nodos).
# Requiere: .env, .env.secrets, .env.cloud.nuevo (EKS_EDGE_IP, EKS_EIP_ALLOC), respaldo/ datos.
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/eksctl/desplegar-eks.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1 AWS_PAGER="" PYTHONIOENCODING=utf-8
R=us-west-2
leer() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }

aws eks update-kubeconfig --region $R --name comedor >/dev/null
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 1 ]; do echo "esperando nodos..."; sleep 15; done

# nodo de entrada: lleva la IP elástica y recibe el tráfico público
NODO=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $NODO entrada=si --overwrite >/dev/null
IID=$(aws ec2 describe-instances --region $R --filters Name=private-dns-name,Values=$NODO --query 'Reservations[0].Instances[0].InstanceId' --output text)
ENI=$(aws ec2 describe-instances --region $R --instance-ids $IID --query 'Reservations[0].Instances[0].NetworkInterfaces[?Attachment.DeviceIndex==`0`].NetworkInterfaceId' --output text)
aws ec2 associate-address --region $R --network-interface-id $ENI --allocation-id $EKS_EIP_ALLOC --allow-reassociation >/dev/null   # EKS agrega más interfaces: se usa la principal
SG=$(aws eks describe-cluster --region $R --name comedor --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
for p in 80 443 3001 3002 3003 8080 8085 5678; do aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port $p --cidr 0.0.0.0/0 >/dev/null 2>&1 || true; done
for ip in $COMENSALES_IP $PAGOS_IP; do aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 4566 --cidr $ip/32 >/dev/null 2>&1 || true; done

kubectl apply -f infra/k8s/eks/storageclass.yaml
kubectl create namespace comedor --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create secret generic comedor \
  --from-literal=mongo-user="$(leer .env MONGO_INITDB_ROOT_USERNAME)" --from-literal=mongo-pass="$(leer .env MONGO_INITDB_ROOT_PASSWORD)" \
  --from-literal=cqrs-user="$(leer .env POSTGRES_CQRS_USER)" --from-literal=cqrs-pass="$(leer .env POSTGRES_CQRS_PASSWORD)" \
  --from-literal=kc-admin="$(leer .env KEYCLOAK_ADMIN)" --from-literal=kc-admin-pass="$(leer respaldo/env.ec2 KEYCLOAK_ADMIN_PASSWORD)" \
  --from-literal=n8n-user="$(leer .env N8N_BASIC_AUTH_USER)" --from-literal=n8n-pass="$(leer respaldo/env.ec2 N8N_BASIC_AUTH_PASSWORD)" \
  --from-literal=stripe="$(leer .env.secrets STRIPE_SECRET_KEY)" --from-literal=telegram="$(leer .env.secrets TELEGRAM_BOT_TOKEN)"   --from-literal=s3-key="$(leer respaldo/s3-bandejas.env S3_ACCESS_KEY_ID)" --from-literal=s3-secret="$(leer respaldo/s3-bandejas.env S3_SECRET_ACCESS_KEY)" \
  --dry-run=client -o yaml | kubectl apply -f -
python infra/ec2/realm.py "$EKS_EDGE_IP" deploy/ec2/realm/comedor-realm.json
kubectl -n comedor create configmap realm --from-file=comedor-realm.json=deploy/ec2/realm/comedor-realm.json --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create configmap flujos-n8n --from-file=automation/n8n/flows --dry-run=client -o yaml | kubectl apply -f -
kubectl -n comedor create configmap init-localstack --from-file=init-localstack.sh=eventbus/infra/init-localstack.sh --dry-run=client -o yaml | kubectl apply -f -

python infra/k8s/eks/generar_aws.py "$EKS_EDGE_IP" "$COMENSALES_IP" "$PAGOS_IP" > infra/k8s/eks/comedor-aws.yaml
kubectl apply -f infra/k8s/eks/comedor-aws.yaml

echo "== datos: esperando a que arranquen las bases"
kubectl -n comedor rollout status deploy/mongo deploy/postgres-cqrs deploy/dynamodb-local --timeout=600s
exec_in() { kubectl -n comedor exec -i deploy/$1 -- "${@:2}"; }
[ -f respaldo/mongo.archive.gz ] && exec_in mongo sh -c 'mongorestore --archive --gzip --drop -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin' < respaldo/mongo.archive.gz 2>&1 | tail -1
exec_in postgres-cqrs sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"' >/dev/null 2>&1 || true
exec_in postgres-cqrs sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < respaldo/cqrs_read.sql >/dev/null 2>&1 || true
kubectl -n comedor rollout status deploy/ia-ml-service --timeout=900s
for t in sagas idempotency_keys; do kubectl -n comedor cp respaldo/dynamodb-$t.json $(kubectl -n comedor get pod -l app=ia-ml-service -o name | head -1 | sed 's#pod/##'):/tmp/dynamodb-$t.json; done
kubectl -n comedor cp infra/ec2/cargar_dynamodb.py $(kubectl -n comedor get pod -l app=ia-ml-service -o name | head -1 | sed 's#pod/##'):/tmp/cargar_dynamodb.py
kubectl -n comedor exec deploy/ia-ml-service -- python /tmp/cargar_dynamodb.py
echo "listo: https://$EKS_EDGE_IP"
