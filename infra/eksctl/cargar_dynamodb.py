"""Carga las sagas y claves de idempotencia respaldadas en DynamoDB real de AWS. Se ejecuta dentro del contenedor ia-ml."""
import json
import os

import boto3

ddb = boto3.client(
    "dynamodb",
    endpoint_url=os.environ.get("DYNAMODB_ENDPOINT") or None,
    region_name=os.environ.get("DYNAMODB_REGION", "us-west-2"),
    aws_access_key_id=os.environ["DYNAMODB_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["DYNAMODB_SECRET_ACCESS_KEY"],
)
for tabla, clave in (("sagas", "sagaId"), ("idempotency_keys", "idempotencyKey")):
    try:
        ddb.create_table(TableName=tabla, AttributeDefinitions=[{"AttributeName": clave, "AttributeType": "S"}],
                         KeySchema=[{"AttributeName": clave, "KeyType": "HASH"}], BillingMode="PAY_PER_REQUEST")
    except ddb.exceptions.ResourceInUseException:
        pass
    items = json.load(open(f"/tmp/dynamodb-{tabla}.json"))
    for it in items:
        ddb.put_item(TableName=tabla, Item=it)
    print(tabla, len(items))
