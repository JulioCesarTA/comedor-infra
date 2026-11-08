#!/usr/bin/env bash
# Enciende los nodos y vuelve a ponerle al proxy de entrada la IP fija (32.187.224.152 = EDGE_IP).
set -a; . ./.env.cloud.nuevo; set +a
export AWS_PAGER=""
eksctl scale nodegroup --cluster comedor --region us-west-2 --name nodos2 --nodes 2 --nodes-min 0
until [ "$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 2 ]; do sleep 10; done
N=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
kubectl label node $N entrada=si --overwrite
IID=$(aws ec2 describe-instances --region us-west-2 --filters Name=private-dns-name,Values=$N --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 associate-address --region us-west-2 --instance-id $IID --allocation-id $EIP_ALLOC >/dev/null
kubectl -n comedor rollout restart deploy/entrada
echo "listo: http://$EDGE_IP:3000"
