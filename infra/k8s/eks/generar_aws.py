"""Genera comedor-aws.yaml: la parte de AWS del sistema para el clúster EKS.

Uso: python infra/k8s/eks/generar_aws.py <IP-publica-del-nodo-de-entrada> <IP-comensales> <IP-pagos> > infra/k8s/eks/comedor-aws.yaml

Qué va en este clúster (SPEC): menu-inventario, ia-ml, api-gateway y la infraestructura de soporte (Mongo, Postgres CQRS, DynamoDB, localstack),
más Keycloak, n8n, graphql-gateway, los frontends y el proxy de entrada con HTTPS.
`comensales` (Azure) y `pagos` (GCP) se llaman por sus URL públicas: se pasan como argumentos.
Los secretos NO van aquí: se crean con desplegar-eks.sh (secret "comedor") y se leen con secretKeyRef.
"""
import sys

EDGE_IP, COMENSALES_IP, PAGOS_IP = sys.argv[1:4]
NS = "comedor"
GHCR = "006419716393.dkr.ecr.us-west-2.amazonaws.com/comedor"   # ECR: los nodos de EKS lo leen con su rol, sin secretos
HOST = EDGE_IP
COMENSALES_URL = f"http://{COMENSALES_IP}:8082"
PAGOS_URL = f"http://{PAGOS_IP}:8083"


def S(clave):
    return {"secret": clave}


def env_yaml(env, indent=8):
    pad = " " * indent
    out = []
    for k, v in env.items():
        if isinstance(v, dict):
            out.append(f"{pad}- name: {k}\n{pad}  valueFrom: {{ secretKeyRef: {{ name: comedor, key: {v['secret']} }} }}")
        else:
            out.append(f'{pad}- name: {k}\n{pad}  value: "{v}"')
    return "\n".join(out)


def pvc(nombre, gi):
    return f"""---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {nombre}
  namespace: {NS}
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: {gi}Gi
"""


def despliegue(nombre, imagen, puerto, env=None, mem="128Mi", limite="512Mi", sonda=None, pull=False, comando=None,
               volmounts="", volumes="", extra_pod="", puertos_extra=(), strategy_recreate=False, sonda_tcp=False):
    """Deployment + Service (ClusterIP) para un componente."""
    sonda_txt = ""
    if sonda:
        sonda_txt = f"""        readinessProbe:
          httpGet: {{ path: {sonda}, port: {puerto} }}
          initialDelaySeconds: 20
          periodSeconds: 10
          failureThreshold: 18
"""
    if sonda_tcp:   # el puerto abre solo cuando el proceso ya arrancó del todo
        sonda_txt = f"""        readinessProbe:
          tcpSocket: {{ port: {puerto} }}
          initialDelaySeconds: 5
          periodSeconds: 5
"""
    pull_txt = "      imagePullSecrets:\n      - name: ghcr\n" if pull else ""
    cmd = f"        command: {comando}\n" if comando else ""
    estrategia = "  strategy:\n    type: Recreate\n" if strategy_recreate else ""
    env_txt = f"        env:\n{env_yaml(env or {})}\n" if env else ""
    puertos = [puerto] + list(puertos_extra)
    return f"""---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {nombre}
  namespace: {NS}
spec:
  replicas: 1
{estrategia}  selector:
    matchLabels: {{ app: {nombre} }}
  template:
    metadata:
      labels: {{ app: {nombre} }}
    spec:
      enableServiceLinks: false   # evita que Kubernetes inyecte variables tipo DYNAMODB_LOCAL_PORT que rompen a localstack
{pull_txt}{extra_pod}      containers:
      - name: {nombre}
        image: {imagen}
        imagePullPolicy: Always
{cmd}        ports:
{chr(10).join(f"        - containerPort: {p}" for p in puertos)}
{env_txt}{sonda_txt}{volmounts}        resources:
          requests: {{ memory: {mem}, cpu: 20m }}
          limits: {{ memory: {limite} }}
{volumes}---
apiVersion: v1
kind: Service
metadata:
  name: {nombre}
  namespace: {NS}
spec:
  selector: {{ app: {nombre} }}
  ports:
{chr(10).join(f"  - {{ name: p{p}, port: {p}, targetPort: {p} }}" for p in puertos)}
"""


def montaje(nombre, ruta, sub=None):
    s = f"        - {{ name: {nombre}, mountPath: {ruta}"
    if sub:
        s += f", subPath: {sub}"
    return s + " }\n"


def mounts(*items):
    return "        volumeMounts:\n" + "".join(items)


def volumes(*items):
    return "      volumes:\n" + "".join(items)


def vol_pvc(nombre, claim):
    return f"      - name: {nombre}\n        persistentVolumeClaim: {{ claimName: {claim} }}\n"


def vol_cm(nombre, cm, modo=None):
    extra = f", defaultMode: {modo}" if modo else ""
    return f"      - name: {nombre}\n        configMap: {{ name: {cm}{extra} }}\n"


AWS_PRUEBA = {"AWS_REGION": "us-east-1", "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test",
              "AWS_ENDPOINT_URL": "http://localstack:4566"}

salida = [f"apiVersion: v1\nkind: Namespace\nmetadata:\n  name: {NS}\n"]

# ------------------------------------------------------------------ datos (en el clúster, con disco persistente)
salida.append(pvc("mongo-datos", 5) + pvc("cqrs-datos", 5) + pvc("ia-datos", 2))
salida.append(despliegue("mongo", "mongo:7", 27017, {"MONGO_INITDB_ROOT_USERNAME": S("mongo-user"), "MONGO_INITDB_ROOT_PASSWORD": S("mongo-pass")},
                         mem="256Mi", limite="768Mi", pull=False, strategy_recreate=True,
                         volmounts=mounts(montaje("datos", "/data/db")), volumes=volumes(vol_pvc("datos", "mongo-datos"))))
salida.append(despliegue("postgres-cqrs", "postgres:16-alpine", 5432, {"POSTGRES_USER": S("cqrs-user"), "POSTGRES_PASSWORD": S("cqrs-pass"), "POSTGRES_DB": "cqrs_read"},
                         mem="128Mi", limite="512Mi", pull=False, strategy_recreate=True,
                         volmounts=mounts(montaje("datos", "/var/lib/postgresql/data", "pgdata")), volumes=volumes(vol_pvc("datos", "cqrs-datos"))))
salida.append(despliegue("localstack", "localstack/localstack:3", 4566, {"SERVICES": "sns,sqs,s3", "DEBUG": "0", "AWS_DEFAULT_REGION": "us-east-1"},
                         mem="400Mi", limite="1Gi", pull=False,
                         volmounts=mounts(montaje("init", "/etc/localstack/init/ready.d/init.sh", "init-localstack.sh")),
                         volumes=volumes(vol_cm("init", "init-localstack", 493))))

# ------------------------------------------------------------------ microservicios de AWS
salida.append(despliegue("menu-inventario-service", f"{GHCR}/menu-inventario-service:latest", 8080, {
    "SPRING_PROFILES_ACTIVE": "docker", "MONGO_USER": S("mongo-user"), "MONGO_PASS": S("mongo-pass"),
    "SPRING_DATA_MONGODB_URI": "mongodb://$(MONGO_USER):$(MONGO_PASS)@mongo:27017/menu_inventario?authSource=admin", **AWS_PRUEBA},
    mem="512Mi", limite="1Gi", sonda="/actuator/health"))
salida.append(despliegue("ia-ml-service", f"{GHCR}/ia-ml-service:latest", 8080, {
    "APP_ENV": "production", "CQRS_USER": S("cqrs-user"), "CQRS_PASS": S("cqrs-pass"),
    "CQRS_DATABASE_URL": "postgresql://$(CQRS_USER):$(CQRS_PASS)@postgres-cqrs:5432/cqrs_read",
    "TELEGRAM_BOT_TOKEN": S("telegram"), "TELEGRAM_API_URL": "https://api.telegram.org", "TELEGRAM_RECEPCION": "n8n", "TZ": "America/La_Paz",
    "KEYCLOAK_URL": "http://keycloak:8080", "KEYCLOAK_REALM": "comedor-uagrm", "KEYCLOAK_ADMIN": S("kc-admin"),
    "KEYCLOAK_ADMIN_PASSWORD": S("kc-admin-pass"), "STRIPE_SECRET_KEY": S("stripe"),
    "DYNAMODB_ENDPOINT": "https://dynamodb.us-west-2.amazonaws.com", "DYNAMODB_REGION": "us-west-2", "DYNAMODB_ACCESS_KEY_ID": S("dynamo-key"),
    "DYNAMODB_SECRET_ACCESS_KEY": S("dynamo-secret"), "COMENSALES_URL": COMENSALES_URL, "PAGOS_URL": PAGOS_URL, **AWS_PRUEBA,
    # S3 real (fotos de bandejas): credenciales propias de solo lectura/escritura sobre ese bucket
    "S3_BANDEJAS_BUCKET": "comedor-uagrm-bandejas-006419716393", "S3_REGION": "us-west-2",
    "S3_ACCESS_KEY_ID": S("s3-key"), "S3_SECRET_ACCESS_KEY": S("s3-secret"),
    # Todas las notificaciones (Telegram y push) las envía n8n
    "N8N_URL": "http://n8n:5678", "N8N_CLAVE": S("n8n-clave")},
    mem="1Gi", limite="3Gi", sonda="/health", strategy_recreate=True,
    # La app corre con el grupo 101: sin esto no puede escribir en el volumen y sus datos se pierden en cada reinicio
    extra_pod="      securityContext:\n        fsGroup: 101\n",
    volmounts=mounts(montaje("datos", "/data")), volumes=volumes(vol_pvc("datos", "ia-datos"))))

# ------------------------------------------------------------------ plataforma
URLS = {"MENU_URL": "http://menu-inventario-service:8080", "COMENSALES_URL": COMENSALES_URL, "PAGOS_URL": PAGOS_URL}
salida.append(despliegue("api-gateway", f"{GHCR}/api-gateway:latest", 8080, {
    "PORT": "8080", "AUTH_DISABLED": "true", "KEYCLOAK_URL": "http://keycloak:8080", "KEYCLOAK_REALM": "comedor-uagrm",
    "KEYCLOAK_ADMIN": S("kc-admin"), "KEYCLOAK_ADMIN_PASSWORD": S("kc-admin-pass"), "IA_URL": "http://ia-ml-service:8080", **URLS}))
salida.append(despliegue("graphql-gateway", f"{GHCR}/graphql-gateway:latest", 4000, {"PORT": "4000", **URLS}, sonda_tcp=True))
salida.append(despliegue("keycloak", "quay.io/keycloak/keycloak:25.0", 8080, {
    "KEYCLOAK_ADMIN": S("kc-admin"), "KEYCLOAK_ADMIN_PASSWORD": S("kc-admin-pass"), "KC_HTTP_ENABLED": "true",
    "KC_HOSTNAME_STRICT": "false", "KC_PROXY_HEADERS": "xforwarded"}, mem="700Mi", limite="1500Mi", pull=False,
    comando='["/opt/keycloak/bin/kc.sh", "start-dev", "--import-realm"]',
    volmounts=mounts(montaje("realm", "/opt/keycloak/data/import")), volumes=volumes(vol_cm("realm", "realm"))))
salida.append(despliegue("n8n", "n8nio/n8n:latest", 5678, {
    "N8N_BASIC_AUTH_ACTIVE": "true", "N8N_BASIC_AUTH_USER": S("n8n-user"), "N8N_BASIC_AUTH_PASSWORD": S("n8n-pass"),
    "N8N_PORT": "5678", "GENERIC_TIMEZONE": "America/La_Paz", "N8N_BLOCK_ENV_ACCESS_IN_NODE": "false", "TELEGRAM_BOT_TOKEN": S("telegram"),
    "NODE_FUNCTION_ALLOW_BUILTIN": "crypto", "N8N_CLAVE": S("n8n-clave"),
    # Firebase Cloud Messaging (push): JSON de la cuenta de servicio, desde respaldo/firebase-admin.json
    "FIREBASE_CREDENCIALES": S("firebase"),
    "IA_URL": "http://ia-ml-service:8080", "MENU_URL": "http://menu-inventario-service:8080", "PAGOS_URL": PAGOS_URL},
    mem="400Mi", limite="1Gi", pull=False,
    comando='["sh", "-c", "for f in /flows/*.json; do n8n import:workflow --input=$f; done; for w in telegramComedor01 notificarComedor01 ordenAprobada01 reposicionInsumos01; do n8n publish:workflow --id=$w; done; exec n8n start"]',
    volmounts=mounts(montaje("flujos", "/flows")), volumes=volumes(vol_cm("flujos", "flujos-n8n"))))
for nombre, img, puerto in [("shell", "shell", 80), ("backoffice-gestion", "backoffice-gestion", 80),
                            ("portal-estudiante", "portal-estudiante", 80), ("inteligencia-negocio", "inteligencia-negocio", 3003)]:
    env = {"API_INTERNAL_URL": "http://api-gateway:8080"} if nombre == "inteligencia-negocio" else None
    salida.append(despliegue(nombre, f"{GHCR}/{img}:latest", puerto, env, mem="64Mi", limite="384Mi"))

# ------------------------------------------------------------------ entrada: nginx con HTTPS en el nodo con IP elástica
RUTAS = [(443, "shell", 80), (3001, "backoffice-gestion", 80), (3002, "portal-estudiante", 80), (3003, "inteligencia-negocio", 3003),
         (8080, "api-gateway", 8080), (8085, "keycloak", 8080), (5678, "n8n", 5678)]
CERT = f"/etc/letsencrypt/live/ip-{HOST}"
bloques = "\n".join(f"""      server {{
        listen {p} ssl;
        ssl_certificate {CERT}/fullchain.pem;
        ssl_certificate_key {CERT}/privkey.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        client_max_body_size 25m;
        location / {{
          proxy_pass http://{s}:{t};
          proxy_http_version 1.1;
          proxy_set_header Host $http_host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto https;
          proxy_set_header X-Forwarded-Host $http_host;
          proxy_set_header X-Forwarded-Port $server_port;
          proxy_set_header Upgrade $http_upgrade;
          proxy_set_header Connection $connection_upgrade;
          proxy_read_timeout 120s;
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
    worker_processes 1;
    events {{}}
    http {{
      map $http_upgrade $connection_upgrade {{ default upgrade; '' close; }}
      server {{
        listen 80;
        location /.well-known/acme-challenge/ {{ root /var/www/html; }}
        location / {{ return 301 https://$host$request_uri; }}
      }}
{bloques}
    }}
    stream {{
      server {{ listen 4566; proxy_pass localstack:4566; }}
    }}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: entrada
  namespace: {NS}
spec:
  replicas: 1
  strategy:
    type: Recreate
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
        command: ["sh", "-c", "until [ -f {CERT}/fullchain.pem ]; do sleep 5; done; nginx -g 'daemon off;' & while sleep 6h; do nginx -s reload; done"]
        volumeMounts:
        - {{ name: conf, mountPath: /etc/nginx/nginx.conf, subPath: nginx.conf }}
        - {{ name: certs, mountPath: /etc/letsencrypt }}
        - {{ name: web, mountPath: /var/www/html }}
        resources:
          requests: {{ memory: 32Mi, cpu: 20m }}
      volumes:
      - name: conf
        configMap: {{ name: entrada-conf }}
      - name: certs
        hostPath: {{ path: /etc/letsencrypt, type: DirectoryOrCreate }}
      - name: web
        hostPath: {{ path: /var/www/html, type: DirectoryOrCreate }}
---
# Certificado de Let's Encrypt para la IP (perfil "shortlived", ~6 días): se pide una vez y se renueva cada 6 horas
apiVersion: batch/v1
kind: Job
metadata:
  name: certificado-inicial
  namespace: {NS}
spec:
  backoffLimit: 20
  template:
    spec:
      restartPolicy: OnFailure
      hostNetwork: true
      nodeSelector: {{ entrada: "si" }}
      containers:
      - name: certbot
        image: certbot/certbot:latest
        args: ["certonly", "--standalone", "--ip-address", "{HOST}", "--preferred-profile", "shortlived", "--cert-name", "ip-{HOST}",
               "--non-interactive", "--agree-tos", "--register-unsafely-without-email"]
        volumeMounts:
        - {{ name: certs, mountPath: /etc/letsencrypt }}
      volumes:
      - name: certs
        hostPath: {{ path: /etc/letsencrypt, type: DirectoryOrCreate }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: renovar-certificado
  namespace: {NS}
spec:
  schedule: "17 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          nodeSelector: {{ entrada: "si" }}
          containers:
          - name: certbot
            image: certbot/certbot:latest
            args: ["renew", "--webroot", "-w", "/var/www/html", "--quiet"]
            volumeMounts:
            - {{ name: certs, mountPath: /etc/letsencrypt }}
            - {{ name: web, mountPath: /var/www/html }}
          volumes:
          - name: certs
            hostPath: {{ path: /etc/letsencrypt, type: DirectoryOrCreate }}
          - name: web
            hostPath: {{ path: /var/www/html, type: DirectoryOrCreate }}
""")

print("\n".join(salida))
