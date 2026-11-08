#!/usr/bin/env bash
# Apaga los nodos (ahorra ~120 USD/mes); queda solo el control plane de EKS. Datos y RDS se conservan.
set -a; . ./.env.cloud.nuevo; set +a
eksctl scale nodegroup --cluster comedor --region us-west-2 --name nodos2 --nodes 0 --nodes-min 0
