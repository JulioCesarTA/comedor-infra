"""Genera comedor.yaml (Deployments + Services + proxy de entrada) para el clúster EKS.

Uso: python infra/k8s/eks/generar.py <cuenta-aws> [version-imagenes]  >  infra/k8s/eks/comedor.yaml
Los secretos NO van aquí: se crean con desplegar.sh (kubectl create secret) y se leen con secretKeyRef.
"""
import sys

CUENTA = sys.argv[1]
VER = sys.argv[2] if len(sys.argv) > 2 else "v1"
REG = f"{CUENTA}.dkr.ecr.us-west-2.amazonaws.com/comedor"
NS = "comedor"


def sec(secreto: str, clave: str) -> dict:
    return {"valueFrom": {"secretKeyRef": {"name": secreto, "key": clave}}}


def env_yaml(env: dict) -> str:
    lineas = []
    for k, v in env.items():
        if isinstance(v, dict):
            s = v["valueFrom"]["secretKeyRef"]
            lineas.append(f"        - name: {k}\n          valueFrom: {{ secretKeyRef: {{ name: {s['name']}, key: {s['key']} }} }}")
        else:
            lineas.append(f"        - name: {k}\n          value: \"{v}\"")
    return "\n".join(lineas) if lineas else ""


AWS = {"AWS_REGION": "us-west-2", "AWS_ACCOUNT_ID": CUENTA,
       "AWS_ACCESS_KEY_ID": sec("aws-app", "id"), "AWS_SECRET_ACCESS_KEY": sec("aws-app", "secret")}


def despliegue(nombre, imagen, puerto, env=None, mem="256Mi", limite="768Mi", sonda=None, montajes="", volumenes="", comando=None):
    env_txt = env_yaml(env or {})
    sonda_txt = ""
    if sonda:
        sonda_txt = f"""        readinessProbe:
          httpGet: {{ path: {sonda}, port: {puerto} }}
          initialDelaySeconds: 20
          periodSeconds: 10
          failureThreshold: 12
"""
    cmd = f"        command: {comando}\n" if comando else ""
    return f"""---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {nombre}
  namespace: {NS}
spec:
  replicas: 1
  selector:
    matchLabels: {{ app: {nombre} }}
  template:
    metadata:
      labels: {{ app: {nombre} }}
    spec:
      containers:
      - name: {nombre}
        image: {imagen}
        imagePullPolicy: Always
{cmd}        ports:
        - containerPort: {puerto}
        env:
{env_txt}
{sonda_txt}        resources:
          requests: {{ memory: {mem}, cpu: 50m }}
          limits: {{ memory: {limite} }}
{montajes}{volumenes}---
apiVersion: v1
kind: Service
metadata:
  name: {nombre}
  namespace: {NS}
spec:
  selector: {{ app: {nombre} }}
  ports:
  - port: {puerto}
    targetPort: {puerto}
"""


def img(n):
    return f"{REG}/{n}:{VER}"


salida = [f"""apiVersion: v1
kind: Namespace
metadata:
  name: {NS}
"""]

salida.append(despliegue("menu-inventario-service", img("menu-inventario"), 8080, {
    "SPRING_PROFILES_ACTIVE": "docker", "SPRING_DATA_MONGODB_URI": sec("comedor", "mongo-uri"),
    "aws_sns_topicDominioMenuArn": f"arn:aws:sns:us-west-2:{CUENTA}:dominio-menu", **AWS}, mem="512Mi", limite="1Gi", sonda="/actuator/health"))
salida.append(despliegue("comensales-reservas-service", img("comensales-reservas"), 8080, {
    "NODE_ENV": "production", "PORT": "8080", "DATABASE_URL": sec("comedor", "url-comensales"), **AWS}, mem="256Mi"))
salida.append(despliegue("pagos-tickets-service", img("pagos-tickets"), 8080, {
    "APP_ENV": "production", "APP_DEBUG": "false", "APP_KEY": sec("comedor", "app-key"), "DB_CONNECTION": "pgsql",
    "DB_HOST": sec("comedor", "rds-host"), "DB_PORT": "5432", "DB_DATABASE": "pagos_tickets", "DB_USERNAME": "postgres",
    "DB_PASSWORD": sec("comedor", "rds-password"), "STRIPE_SECRET_KEY": sec("comedor", "stripe"), **AWS}, mem="256Mi"))
salida.append(despliegue("ia-ml-service", img("ia-ml"), 8080, {
    "APP_ENV": "production", "CQRS_DATABASE_URL": sec("comedor", "url-cqrs"), "TELEGRAM_BOT_TOKEN": sec("comedor", "telegram"),
    "TELEGRAM_API_URL": "https://api.telegram.org", "TELEGRAM_RECEPCION": "n8n", "TZ": "America/La_Paz",
    "KEYCLOAK_URL": "http://keycloak:8080", "KEYCLOAK_REALM": "comedor-uagrm", "KEYCLOAK_ADMIN": sec("comedor", "kc-admin"),
    "KEYCLOAK_ADMIN_PASSWORD": sec("comedor", "kc-admin-password"), "STRIPE_SECRET_KEY": sec("comedor", "stripe"), **AWS},
    mem="1Gi", limite="3Gi", sonda="/health"))
salida.append(despliegue("api-gateway", img("api-gateway"), 8080, {
    "PORT": "8080", "AUTH_DISABLED": "true", "KEYCLOAK_URL": "http://keycloak:8080", "KEYCLOAK_REALM": "comedor-uagrm",
    "KEYCLOAK_ADMIN": sec("comedor", "kc-admin"), "KEYCLOAK_ADMIN_PASSWORD": sec("comedor", "kc-admin-password"),
    "MENU_URL": "http://menu-inventario-service:8080", "COMENSALES_URL": "http://comensales-reservas-service:8080",
    "PAGOS_URL": "http://pagos-tickets-service:8080", "IA_URL": "http://ia-ml-service:8080"}, mem="128Mi"))
salida.append(despliegue("graphql-gateway", img("graphql-gateway"), 4000, {
    "PORT": "4000", "MENU_URL": "http://menu-inventario-service:8080", "COMENSALES_URL": "http://comensales-reservas-service:8080",
    "PAGOS_URL": "http://pagos-tickets-service:8080"}, mem="128Mi"))
salida.append(despliegue("shell", img("shell"), 80, mem="32Mi", limite="128Mi"))
salida.append(despliegue("backoffice-gestion", img("backoffice"), 80, mem="32Mi", limite="128Mi"))
salida.append(despliegue("portal-estudiante", img("portal"), 80, mem="32Mi", limite="128Mi"))
salida.append(despliegue("bi", img("bi"), 3003, {"API_INTERNAL_URL": "http://api-gateway:8080"}, mem="128Mi", limite="512Mi"))
salida.append(despliegue("keycloak", "quay.io/keycloak/keycloak:25.0", 8080, {
    "KC_DB": "postgres", "KC_DB_URL": sec("comedor", "url-keycloak-jdbc"), "KC_DB_USERNAME": "postgres",
    "KC_DB_PASSWORD": sec("comedor", "rds-password"), "KEYCLOAK_ADMIN": sec("comedor", "kc-admin"),
    "KEYCLOAK_ADMIN_PASSWORD": sec("comedor", "kc-admin-password"), "KC_HTTP_ENABLED": "true",
    "KC_HOSTNAME_STRICT": "false", "KC_PROXY_HEADERS": "xforwarded"}, mem="700Mi", limite="1500Mi",
    comando='["/opt/keycloak/bin/kc.sh", "start-dev", "--import-realm"]',
    montajes="        volumeMounts:\n        - { name: realm, mountPath: /opt/keycloak/data/import }\n",
    volumenes="      volumes:\n      - name: realm\n        configMap: { name: realm }\n"))

# n8n: importa y activa los flujos al arrancar (los flujos viven en el ConfigMap "flujos-n8n")
salida.append(despliegue("n8n", "n8nio/n8n:latest", 5678, {
    "N8N_BASIC_AUTH_ACTIVE": "true", "N8N_BASIC_AUTH_USER": sec("comedor", "n8n-user"),
    "N8N_BASIC_AUTH_PASSWORD": sec("comedor", "n8n-password"), "N8N_PORT": "5678", "GENERIC_TIMEZONE": "America/La_Paz",
    "N8N_BLOCK_ENV_ACCESS_IN_NODE": "false", "TELEGRAM_BOT_TOKEN": sec("comedor", "telegram")}, mem="400Mi", limite="1Gi",
    comando='["sh", "-c", "for f in /flows/*.json; do n8n import:workflow --input=$f; done; n8n update:workflow --id=telegramComedor01 --active=true; exec n8n start"]',
    montajes="        volumeMounts:\n        - { name: flujos, mountPath: /flows }\n",
    volumenes="      volumes:\n      - name: flujos\n        configMap: { name: flujos-n8n }\n"))

# Proxy de entrada: un solo balanceador (NLB) que expone los mismos puertos que en local (3000-3003, 8080, 8085, 5678)
RUTAS = [(3000, "shell", 80), (3001, "backoffice-gestion", 80), (3002, "portal-estudiante", 80), (3003, "bi", 3003),
         (8080, "api-gateway", 8080), (8085, "keycloak", 8080), (5678, "n8n", 5678)]
bloques = "\n".join(f"""    server {{
      listen {p};
      location / {{
        proxy_pass http://{s}:{t};
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Forwarded-Host $http_host;
        proxy_set_header X-Forwarded-Proto http;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_read_timeout 120s;
        client_max_body_size 25m;
      }}
    }}""" for p, s, t in RUTAS)
salida.append(f"""---
apiVersion: v1
kind: ConfigMap
metadata:
  name: entrada-conf
  namespace: {NS}
data:
  nginx.conf: |
    events {{}}
    http {{
      map $http_upgrade $connection_upgrade {{ default upgrade; '' close; }}
{bloques}
    }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: entrada
  namespace: {NS}
spec:
  replicas: 1
  selector:
    matchLabels: {{ app: entrada }}
  template:
    metadata:
      labels: {{ app: entrada }}
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      nodeSelector: {{ entrada: "si" }}
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
{chr(10).join(f"        - containerPort: {p}" for p, _, _ in RUTAS)}
        volumeMounts:
        - {{ name: conf, mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf }}
        resources:
          requests: {{ memory: 32Mi, cpu: 20m }}
      volumes:
      - name: conf
        configMap: {{ name: entrada-conf }}
""")

print("\n".join(salida))
