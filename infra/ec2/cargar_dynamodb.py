"""Carga las sagas y claves de idempotencia respaldadas en el DynamoDB local. Se ejecuta dentro del contenedor ia-ml."""
import json
import os

import boto3

ddb = boto3.client(
    "dynamodb",
    endpoint_url=os.environ["DYNAMODB_ENDPOINT"],
    region_name=os.environ.get("AWS_REGION", "us-east-1"),
    aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID", "test"),
    aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY", "test"),
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
