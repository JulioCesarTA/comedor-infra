#!/usr/bin/env bash
# ============================================================================
# init-localstack.sh — se ejecuta cuando LocalStack termina de arrancar.
# Crea:
#   - Tablas DynamoDB: idempotency_keys, sagas
#   - Topics SNS: dominio.menu, dominio.reservas, dominio.pagos
#   - Colas SQS: una por consumidor + DLQ
#   - Subscripciones SNS -> SQS
# ============================================================================
set -euo pipefail

echo "[init-localstack] creando recursos..."

export AWS_PAGER=""
AWSLOCAL="awslocal --region ${AWS_DEFAULT_REGION:-us-east-1}"

# ----------------- DynamoDB -----------------
$AWSLOCAL dynamodb create-table \
  --table-name idempotency_keys \
  --attribute-definitions AttributeName=idempotencyKey,AttributeType=S \
  --key-schema AttributeName=idempotencyKey,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  >/dev/null 2>&1 || echo "  [dynamodb] idempotency_keys ya existe"

$AWSLOCAL dynamodb create-table \
  --table-name sagas \
  --attribute-definitions AttributeName=sagaId,AttributeType=S \
  --key-schema AttributeName=sagaId,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  >/dev/null 2>&1 || echo "  [dynamodb] sagas ya existe"

# ----------------- SNS Topics -----------------
for topic in dominio-menu dominio-reservas dominio-pagos; do
  $AWSLOCAL sns create-topic --name "$topic" >/dev/null
  echo "  [sns] topic $topic listo"
done

# ----------------- SQS Queues -----------------
for queue in cqrs-projector saga-events notificaciones; do
  $AWSLOCAL sqs create-queue --queue-name "$queue" >/dev/null
  $AWSLOCAL sqs create-queue --queue-name "${queue}-dlq" >/dev/null
  echo "  [sqs] cola $queue (+ dlq) lista"
done

# ----------------- Subscripciones SNS -> SQS -----------------
ACCOUNT_ID=000000000000
REGION=${AWS_DEFAULT_REGION:-us-east-1}

for topic in dominio-menu dominio-reservas dominio-pagos; do
  TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${topic}"
  for queue in cqrs-projector saga-events; do
    QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${queue}"
    $AWSLOCAL sns subscribe \
      --topic-arn "$TOPIC_ARN" \
      --protocol sqs \
      --notification-endpoint "$QUEUE_ARN" \
      --attributes RawMessageDelivery=true \
      >/dev/null
  done
done
echo "  [sns->sqs] suscripciones listas"

# ----------------- S3 buckets -----------------
for bucket in bandejas-fotos reportes-generados ml-artifacts; do
  $AWSLOCAL s3 mb "s3://${bucket}" >/dev/null 2>&1 || echo "  [s3] bucket $bucket ya existe"
done

echo "[init-localstack] ✅ listo."
