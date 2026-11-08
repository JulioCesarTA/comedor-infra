# ================================================================
# Comedor UAGRM — comandos de desarrollo
# Uso: make <target>
# En Windows: usar `make` desde Git Bash o `wsl make`
# ================================================================

.PHONY: help up down restart logs ps clean build test \
        up-infra up-services aws-local-init \
        deploy-aws deploy-azure deploy-gcp

help:
	@echo "Comedor UAGRM - comandos disponibles:"
	@echo ""
	@echo "  make up                levanta TODO el stack local (infra + microservicios)"
	@echo "  make up-infra          solo infraestructura (BDs, Keycloak, LocalStack, n8n)"
	@echo "  make up-services       solo los 4 microservicios"
	@echo "  make down              detiene y borra contenedores"
	@echo "  make restart           restart completo"
	@echo "  make logs              tail de logs"
	@echo "  make ps                estado de contenedores"
	@echo "  make clean             borra TODO (contenedores, volúmenes, redes)"
	@echo "  make build             rebuild de imágenes locales"
	@echo "  make test              corre tests de los 4 servicios"
	@echo "  make aws-local-init    (re)crea tablas DynamoDB + topics SNS en LocalStack"
	@echo "  make deploy-aws        aplica K8s a EKS"
	@echo "  make deploy-azure      aplica K8s a AKS"
	@echo "  make deploy-gcp        aplica K8s a GKE"

up:
	docker compose up -d --build
	@echo "✅ Stack arriba. Dashboards:"
	@echo "   - menu-inventario:     http://localhost:8081/actuator/health"
	@echo "   - comensales-reservas: http://localhost:8082/health"
	@echo "   - pagos-tickets:       http://localhost:8083/health"
	@echo "   - ia-ml:               http://localhost:8084/health"
	@echo "   - Keycloak:            http://localhost:8085  (admin/admin)"
	@echo "   - n8n:                 http://localhost:5678  (admin/admin123)"

up-infra:
	docker compose up -d mongo postgres-comensales postgres-pagos postgres-cqrs \
		dynamodb-local localstack keycloak n8n

up-services:
	docker compose up -d --build \
		menu-inventario-service comensales-reservas-service \
		pagos-tickets-service ia-ml-service

down:
	docker compose down

restart: down up

logs:
	docker compose logs -f --tail=100

ps:
	docker compose ps

clean:
	docker compose down -v --remove-orphans
	@echo "🧹 Volúmenes y contenedores borrados."

build:
	docker compose build --no-cache

test:
	cd ../menu-inventario-service && ./mvnw -q test || true
	cd ../comensales-reservas-service && npm test || true
	cd ../pagos-tickets-service && ./vendor/bin/phpunit || true
	cd ../ia-ml-service && python -m pytest -q || true

aws-local-init:
	docker exec comedor-localstack bash /etc/localstack/init/ready.d/init.sh

# ---------- Despliegue multi-nube (requiere kubectl + credenciales) ----------
deploy-aws:
	kubectl --context eks-comedor apply -R -f infra/k8s/aws/

deploy-azure:
	kubectl --context aks-comedor apply -R -f infra/k8s/azure/

deploy-gcp:
	kubectl --context gke-comedor apply -R -f infra/k8s/gcp/
