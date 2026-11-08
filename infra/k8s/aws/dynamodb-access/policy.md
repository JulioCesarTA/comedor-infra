# Acceso DynamoDB cross-cloud (SPEC §1)

- DynamoDB vive **solo** en AWS.
- `comensales-reservas-service` (Azure/AKS) y `pagos-tickets-service` (GCP/GKE) acceden a DynamoDB **vía HTTPS autenticada con IAM**, nunca con SDK directo cross-cloud.
- Endpoint autorizado: `https://api.comedor.uagrm.cloud/sagas/*` y `/idempotency/*`.
- El `ia-ml-service` (que corre en EKS) sí usa SDK directo (IRSA).

## IAM Policy (AWS) — mínimo privilegio
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem", "dynamodb:Query"],
      "Resource": [
        "arn:aws:dynamodb:us-east-1:${AWS_ACCOUNT_ID}:table/idempotency_keys",
        "arn:aws:dynamodb:us-east-1:${AWS_ACCOUNT_ID}:table/sagas"
      ]
    }
  ]
}
```

Esta policy la asumen los roles IRSA de `menu-inventario-sa` e `ia-ml-sa` en EKS.
Para Azure/GCP, el acceso lo mediatiza el API Gateway en AWS que firma las requests con IAM del cluster.
