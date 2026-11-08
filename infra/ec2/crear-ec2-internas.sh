#!/usr/bin/env bash
# Crea las 2 EC2 internas (datos y negocio) en la misma VPC que la EC2 web. Sin IP pública abierta: solo SSH desde tu IP y tráfico de la VPC.
# Uso: set -a; . ./.env.cloud.nuevo; set +a; bash infra/ec2/crear-ec2-internas.sh
set -euo pipefail
export AWS_PAGER="" MSYS_NO_PATHCONV=1
R=${AWS_REGION:-us-west-2}
MI_IP=$(curl -s https://checkip.amazonaws.com | tr -d '\n')
VPC=$(aws ec2 describe-vpcs --region $R --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
SG=$(aws ec2 create-security-group --region $R --group-name ec2-comedor-interna --description "Comedor datos y negocio" --vpc-id $VPC --query GroupId --output text)
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol tcp --port 22 --cidr $MI_IP/32 >/dev/null
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol -1 --source-group $SG >/dev/null
aws ec2 authorize-security-group-ingress --region $R --group-id $SG --protocol -1 --source-group $EC2_SG >/dev/null
AMI=$(aws ec2 describe-images --region $R --owners 099720109477 --filters 'Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*' 'Name=state,Values=available' --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
cat > .userdata.tmp <<'UD'
#!/bin/bash
set -e
fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile && echo '/swapfile none swap sw 0 0' >> /etc/fstab
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
touch /var/lib/cloud/instance/listo-comedor
UD
crear() {  # nombre tipo
  aws ec2 run-instances --region $R --image-id $AMI --instance-type $2 --key-name ec2-comedor --security-group-ids $SG \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=40,VolumeType=gp3}' --user-data file://.userdata.tmp \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=comedor-$1}]" --query 'Instances[0].InstanceId' --output text
}
ID_DATOS=$(crear datos c7i-flex.large); ID_NEGOCIO=$(crear negocio m7i-flex.large)
rm -f .userdata.tmp
aws ec2 wait instance-running --region $R --instance-ids $ID_DATOS $ID_NEGOCIO
info() { aws ec2 describe-instances --region $R --instance-ids $1 --query "Reservations[0].Instances[0].[$2]" --output text; }
printf 'EC2_SG_INTERNA=%s\nDATOS_ID=%s\nDATOS_IP=%s\nDATOS_PRIV=%s\nNEGOCIO_ID=%s\nNEGOCIO_IP=%s\nNEGOCIO_PRIV=%s\nWEB_PRIV=%s\n' \
  "$SG" "$ID_DATOS" "$(info $ID_DATOS PublicIpAddress)" "$(info $ID_DATOS PrivateIpAddress)" \
  "$ID_NEGOCIO" "$(info $ID_NEGOCIO PublicIpAddress)" "$(info $ID_NEGOCIO PrivateIpAddress)" \
  "$(info $EC2_ID PrivateIpAddress)" >> .env.cloud.nuevo
echo "datos $ID_DATOS / negocio $ID_NEGOCIO creados"
