#!/usr/bin/env bash
# Recursos de AWS que no son Kubernetes: DynamoDB, SNS/SQS, S3, ECR y el usuario IAM de las aplicaciones.
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/eksctl/recursos-aws.sh
set -euo pipefail
export AWS_PAGER=""
R=${AWS_REGION:-us-west-2}
CUENTA=$(aws sts get-caller-identity --query Account --output text)

# ---- DynamoDB ----
aws dynamodb create-table --region $R --table-name sagas --attribute-definitions AttributeName=sagaId,AttributeType=S \
  --key-schema AttributeName=sagaId,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null 2>&1 || echo "sagas ya existe"
aws dynamodb create-table --region $R --table-name idempotency_keys --attribute-definitions AttributeName=idempotencyKey,AttributeType=S \
  --key-schema AttributeName=idempotencyKey,KeyType=HASH --billing-mode PAY_PER_REQUEST >/dev/null 2>&1 || echo "idempotency_keys ya existe"

# ---- SNS + SQS (temas por dominio, una cola por consumidor, entrega raw) ----
for t in dominio-menu dominio-reservas dominio-pagos; do aws sns create-topic --region $R --name $t >/dev/null; done
for q in cqrs-projector saga-events notificaciones; do
  url=$(aws sqs create-queue --region $R --queue-name $q --query QueueUrl --output text)
  qarn=arn:aws:sqs:$R:$CUENTA:$q
  politica=$(printf '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"sns.amazonaws.com"},"Action":"sqs:SendMessage","Resource":"%s","Condition":{"ArnLike":{"aws:SourceArn":"arn:aws:sns:%s:%s:dominio-*"}}}]}' "$qarn" "$R" "$CUENTA")
  python -c "import json,sys;print(json.dumps({'Policy':sys.argv[1]}))" "$politica" > .q-attr.tmp.json
  aws sqs set-queue-attributes --region $R --queue-url "$url" --attributes file://.q-attr.tmp.json
done
suscribir() {
  aws sns subscribe --region $R --topic-arn arn:aws:sns:$R:$CUENTA:$1 --protocol sqs \
    --notification-endpoint arn:aws:sqs:$R:$CUENTA:$2 --attributes RawMessageDelivery=true >/dev/null
}
suscribir dominio-reservas saga-events; suscribir dominio-menu saga-events; suscribir dominio-pagos saga-events
suscribir dominio-menu cqrs-projector; suscribir dominio-reservas cqrs-projector; suscribir dominio-pagos cqrs-projector

# ---- S3 (fotos de bandejas) ----
aws s3api create-bucket --region $R --bucket comedor-uagrm-bandejas-fotos-$CUENTA \
  --create-bucket-configuration LocationConstraint=$R >/dev/null 2>&1 || echo "bucket ya existe"

# ---- ECR (una imagen por componente) ----
for r in menu-inventario comensales-reservas pagos-tickets ia-ml api-gateway graphql-gateway shell backoffice portal bi; do
  aws ecr create-repository --region $R --repository-name comedor/$r >/dev/null 2>&1 || echo "ecr $r ya existe"
done

# ---- Usuario IAM solo para las aplicaciones (permisos mínimos) ----
aws iam create-user --user-name comedor-app >/dev/null 2>&1 || echo "usuario comedor-app ya existe"
cat > .politica-app.tmp.json <<POL
{"Version":"2012-10-17","Statement":[
 {"Effect":"Allow","Action":["dynamodb:*"],"Resource":"arn:aws:dynamodb:$R:$CUENTA:table/*"},
 {"Effect":"Allow","Action":["sns:*"],"Resource":"arn:aws:sns:$R:$CUENTA:dominio-*"},
 {"Effect":"Allow","Action":["sqs:*"],"Resource":"arn:aws:sqs:$R:$CUENTA:*"},
 {"Effect":"Allow","Action":["s3:*"],"Resource":["arn:aws:s3:::comedor-uagrm-bandejas-fotos-$CUENTA","arn:aws:s3:::comedor-uagrm-bandejas-fotos-$CUENTA/*"]}
]}
POL
aws iam put-user-policy --user-name comedor-app --policy-name comedor-app --policy-document file://.politica-app.tmp.json
echo "listo: cuenta $CUENTA"
rm -f .q-attr.tmp.json .politica-app.tmp.json
