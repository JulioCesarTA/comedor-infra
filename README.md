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
| `docker-compose.cloud.yml` | código local con datos en la nube (RDS, Atlas, DynamoDB) |
| `auth/keycloak/` | realm de Keycloak (roles, clientes OIDC, usuarios demo) |
| `automation/n8n/flows/` | flujos de n8n: bot de Telegram y reposición de insumos |
| `eventbus/infra/` | temas SNS y colas SQS (script de localstack) |
| `infra/k8s/eks/` · `azure/` · `gcp/` | manifiestos de Kubernetes: AWS (generados por `generar_aws.py`), Azure y GCP |
| `infra/terraform/{aws,azure,gcp}/` | EKS/AKS/GKE, bases de datos gestionadas |
| `infra/eksctl/` | clúster EKS con `eksctl`, despliegue de AWS, encender/apagar nodos, RDS y recursos de AWS |
| `docs/` | especificación (SPEC), checklist y notas de la materia |

## Dónde corre cada cosa (multi-nube, todo en Kubernetes)

| Nube | Clúster | Qué corre |
|---|---|---|
| AWS | EKS `comedor` (us-west-2) | `menu-inventario`, `ia-ml`, gateways, frontends, Keycloak, n8n, Mongo, Postgres CQRS, DynamoDB local, localstack y el nginx de entrada con HTTPS |
| Azure | AKS `comedor-aks` (centralus) | `comensales-reservas` y su Postgres |
| GCP | GKE `comedor-gke` (us-central1-a) | `pagos-tickets` y su Postgres |

La entrada pública es `https://<IP elástica del nodo de EKS>` (certificado de Let's Encrypt para la IP, se renueva solo cada 6 horas).
Esta cuenta de AWS no permite balanceadores de carga, así que el nginx corre en un nodo con IP fija (`hostNetwork`).

| Para | Usa |
|---|---|
| Crear el clúster EKS | `infra/eksctl/cluster-eks.yaml` (`eksctl create cluster -f ... --without-nodegroup`, luego `eksctl create nodegroup -f ...`) |
| Desplegar la parte de AWS | `infra/eksctl/desplegar-eks.sh` (manifiestos generados por `infra/k8s/eks/generar_aws.py`) |
| Desplegar `pagos` en GCP | `infra/gcp/desplegar-gcp.ps1` (manifiesto en `infra/k8s/gcp/`) |
| Desplegar `comensales` en Azure | `infra/azure/desplegar-azure.sh` (manifiesto en `infra/k8s/azure/`) |

## Despliegue automático (commit → producción)

Cada repositorio de servicio tiene `.github/workflows/cd.yml`: al hacer commit en `main`, un *runner* instalado en el PC construye la imagen
(con el caché de Docker), la sube a su registro y reinicia el servicio en el clúster de su nube.

| Repositorio | Registro | Clúster |
|---|---|---|
| `menu-inventario-service`, `ia-ml-service`, `comedor-clientes` | ECR (AWS) | EKS |
| `pagos-tickets-service` | GHCR (público) | GKE |
| `comensales-reservas-service` | GHCR (público) | AKS |

Los runners viven en `C:ctions-runner\<repo>`; si se reinicia el PC hay que ejecutar `iniciar-runners.bat` y tener Docker Desktop abierto.
Secretos de cada repositorio: AWS (usuario `comedor-ci`, solo ECR y el namespace `comedor`), `GCP_SA_KEY` y `AZURE_*`.

## Secretos (no están en git)

`.env`, `.env.secrets`, `.env.cloud*`, `respaldo/`, `CREDENCIALES.local.md` y `deploy/ec2/realm/` están en `.gitignore`.
Los workflows de CD de cada servicio necesitan el secreto `INFRA_REPO_TOKEN` (acceso de lectura a este repositorio).
