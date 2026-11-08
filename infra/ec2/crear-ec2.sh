#!/usr/bin/env bash
# Crea la EC2 donde corre TODO el proyecto (docker compose + nginx con HTTPS).
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/ec2/crear-ec2.sh
# Deja en .env.cloud.nuevo: EC2_ID, EC2_IP, EC2_EIP_ALLOC, EC2_HOST (nombre sslip.io con HTTPS) y guarda la llave en respaldo/ec2-comedor.pem
set -euo pipefail
export AWS_PAGER=""
export MSYS_NO_PATHCONV=1
R=${AWS_REGION:-us-west-2}
VPC=$(aws ec2 describe-vpcs --region $R --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
MI_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')

# reintentos: limpia restos de una ejecución anterior fallida
aws ec2 delete-key-pair --region $R --key-name ec2-comedor >/dev/null 2>&1 || true
aws ec2 delete-security-group --region $R --group-name ec2-comedor >/dev/null 2>&1 || true
mkdir -p respaldo
aws ec2 create-key-pair --region $R --key-name ec2-comedor --query KeyMaterial --output text > respaldo/ec2-comedor.pem
chmod 600 respaldo/ec2-comedor.pem

SG=$(aws ec2 create-security-group --region $R --group-name ec2-comedor --description "Comedor UAGRM" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 22 --cidr $MI_IP/32 >/dev/null
for p in 80 443 3001 3002 3003 8080 8085 5678; do
  aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port $p --cidr 0.0.0.0/0 >/dev/null
done

AMI=$(aws ec2 describe-images --region $R --owners 099720109477 --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' 'Name=state,Values=available' --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
cat > .userdata.tmp <<'UD'
#!/bin/bash
set -e
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y nginx certbot ca-certificates curl
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
touch /var/lib/cloud/instance/listo-comedor
UD
IID=$(aws ec2 run-instances --region $R --image-id $AMI --instance-type m7i-flex.large --key-name ec2-comedor \
  --security-group-ids $SG --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=60,VolumeType=gp3}' \
  --user-data file://.userdata.tmp --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=comedor-uagrm}]' \
  --query 'Instances[0].InstanceId' --output text)
rm -f .userdata.tmp
aws ec2 wait instance-running --region $R --instance-ids $IID
EIP=$(aws ec2 allocate-address --region $R --domain vpc --query '[AllocationId,PublicIp]' --output text)
ALLOC=$(echo $EIP | cut -d' ' -f1); IP=$(echo $EIP | cut -d' ' -f2)
aws ec2 associate-address --region $R --instance-id $IID --allocation-id $ALLOC >/dev/null
HOST="$(echo $IP | tr . -).sslip.io"
printf 'EC2_ID=%s\nEC2_SG=%s\nEC2_IP=%s\nEC2_EIP_ALLOC=%s\nEC2_HOST=%s\n' "$IID" "$SG" "$IP" "$ALLOC" "$HOST" >> .env.cloud.nuevo
echo "EC2 $IID en $IP  ->  https://$HOST"
