#!/usr/bin/env bash
# Crea el RDS Postgres en la VPC del clúster EKS (solo accesible desde dentro de la VPC).
# Guarda RDS_HOST y RDS_PASSWORD en .env.cloud.nuevo.
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/eksctl/crear-rds.sh
set -euo pipefail
export AWS_PAGER=""
R=${AWS_REGION:-us-west-2}

VPC=$(aws eks describe-cluster --region $R --name comedor --query 'cluster.resourcesVpcConfig.vpcId' --output text)
CIDR=$(aws ec2 describe-vpcs --region $R --vpc-ids $VPC --query 'Vpcs[0].CidrBlock' --output text)
SUBREDES=$(aws eks describe-cluster --region $R --name comedor --query 'cluster.resourcesVpcConfig.subnetIds' --output text)

aws rds create-db-subnet-group --region $R --db-subnet-group-name comedor-pg --db-subnet-group-description comedor \
  --subnet-ids $SUBREDES >/dev/null 2>&1 || echo "subnet group ya existe"
SG=$(aws ec2 create-security-group --region $R --group-name comedor-pg --description "Postgres comedor" --vpc-id $VPC \
  --query GroupId --output text 2>/dev/null || aws ec2 describe-security-groups --region $R --filters Name=group-name,Values=comedor-pg Name=vpc-id,Values=$VPC --query 'SecurityGroups[0].GroupId' --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 5432 --cidr $CIDR >/dev/null 2>&1 || true

PASS=$(python -c "import secrets;print(secrets.token_hex(12))")
aws rds create-db-instance --region $R --db-instance-identifier comedor-pg --db-instance-class db.t3.micro \
  --engine postgres --allocated-storage 20 --master-username postgres --master-user-password "$PASS" \
  --db-subnet-group-name comedor-pg --vpc-security-group-ids $SG --no-publicly-accessible --backup-retention-period 0 \
  --no-multi-az --storage-type gp3 >/dev/null
echo "esperando a que el RDS esté disponible (unos 8 minutos)..."
aws rds wait db-instance-available --region $R --db-instance-identifier comedor-pg
HOST=$(aws rds describe-db-instances --region $R --db-instance-identifier comedor-pg --query 'DBInstances[0].Endpoint.Address' --output text)
printf 'RDS_HOST=%s\nRDS_PASSWORD=%s\n' "$HOST" "$PASS" >> .env.cloud.nuevo
echo "RDS listo: $HOST"
