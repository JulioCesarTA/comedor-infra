# comedor-infra

Infraestructura y plataforma del Comedor Universitario UAGRM: cómo se levanta y se despliega todo el sistema.

## Los 6 repositorios

| Repositorio | Contenido | Nube destino |
|---|---|---|
| [`menu-inventario-service`](https://github.com/JulioCesarTA/menu-inventario-service) | Java · DDD · MongoDB | AWS |
| [`comensales-reservas-service`](https://github.com/JulioCesarTA/comensales-reservas-service) | NestJS · Clean · PostgreSQL | Azure |
| [`pagos-tickets-service`](https://github.com/JulioCesarTA/pagos-tickets-service) | PHP · Hexagonal · PostgreSQL | GCP |
| [`ia-ml-service`](https://github.com/JulioCesarTA/ia-ml-service) | FastAPI · capas · CQRS + DynamoDB | AWS |
| [`comedor-clientes`](https://github.com/JulioCesarTA/comedor-clientes) | gateways, frontends y app móvil | — |
| `comedor-infra` (este) | compose, Kubernetes, Terraform, Keycloak, n8n, bus de eventos, scripts de despliegue, documentación | — |

## Levantar todo en local

```bash
git clone https://github.com/JulioCesarTA/comedor-infra && cd comedor-infra
bash clonar-todo.sh          # clona los otros 5 repositorios en la carpeta de al lado
cp .env.example .env         # y completa .env.secrets (Stripe, Telegram) si los usas
docker compose up -d --build
```

Quedan así, uno junto al otro (el `docker-compose.yml` usa `build: ../<repositorio>`):

```
comedor/
├── comedor-infra/
├── comedor-clientes/
├── menu-inventario-service/
├── comensales-reservas-service/
├── pagos-tickets-service/
└── ia-ml-service/
```

## Qué hay aquí

| Ruta | Para qué |
|---|---|
| `docker-compose.yml` | stack completo en local (4 microservicios, Mongo, 3 Postgres, DynamoDB local, localstack, Keycloak, n8n, gateways y frontends) |
| `docker-compose.ec2.yml` | superposición para el despliegue en EC2 con HTTPS (un servidor por microservicio) |
| `docker-compose.cloud.yml` | código local con datos en la nube (RDS, Atlas, DynamoDB) |
| `auth/keycloak/` | realm de Keycloak (roles, clientes OIDC, usuarios demo) |
| `automation/n8n/flows/` | flujos de n8n: bot de Telegram y reposición de insumos |
| `eventbus/infra/` | temas SNS y colas SQS (script de localstack) |
| `infra/k8s/{aws,azure,gcp}/` | manifiestos de Kubernetes por servicio y por nube |
| `infra/terraform/{aws,azure,gcp}/` | EKS/AKS/GKE, bases de datos gestionadas |
| `infra/eksctl/` | clúster EKS con `eksctl` y recursos de AWS |
| `infra/ec2/` | despliegue en EC2: servidores, nginx con Let's Encrypt, carga de datos |
| `docs/` | especificación (SPEC), checklist y notas de la materia |

## Despliegue en EC2 (HTTPS)

```bash
set -a; . ./.env.cloud.nuevo; set +a
bash infra/ec2/crear-ec2.sh             # servidor comedor-stack (nginx + IP elástica)
bash infra/ec2/crear-ec2-internas.sh    # servidores internos
bash infra/ec2/desplegar-ec2.sh         # menu -> comensales -> pagos -> stack
```

Las imágenes se construyen en tu PC y se suben a ECR; los servidores solo hacen `pull`.

## Secretos (no están en git)

`.env`, `.env.secrets`, `.env.cloud*`, `respaldo/`, `CREDENCIALES.local.md` y `deploy/ec2/realm/` están en `.gitignore`.
Los workflows de CD de cada servicio necesitan el secreto `INFRA_REPO_TOKEN` (acceso de lectura a este repositorio).
