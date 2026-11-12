#!/usr/bin/env bash
# Despliega comensales-reservas-service (con su Postgres) en el clúster AKS "comedor-aks" (Azure).
# Requiere: respaldo/kube-aks.yaml (kubeconfig de administrador), .env, .env.cloud.nuevo (EKS_EDGE_IP), respaldo/comensales_reservas.sql
# El kubeconfig se obtiene con la API de Azure (ver infra/azure/obtener_kubeconfig.py).
set -euo pipefail
export MSYS_NO_PATHCONV=1
leer() { grep -E "^$2=" "$1" | head -1 | cut -d= -f2-; }
export KUBECONFIG="$(pwd -W 2>/dev/null || pwd)/respaldo/kube-aks.yaml"
kubectl -n comedor create secret generic comensales-secretos \
  --from-literal=db-user="$(leer .env POSTGRES_COMENSALES_USER)" --from-literal=db-pass="$(leer .env POSTGRES_COMENSALES_PASSWORD)" \
  --dry-run=client -o yaml | kubectl apply -f -
sed "s#__EKS_EDGE_IP__#$(leer .env.cloud.nuevo EKS_EDGE_IP)#" infra/k8s/azure/comensales-reservas-service/comensales.yaml | kubectl apply -f -
kubectl -n comedor rollout status deploy/postgres-comensales --timeout=300s
PG=$(kubectl -n comedor get pod -l app=postgres-comensales -o jsonpath='{.items[0].metadata.name}')
# El respaldo solo se carga en una base VACÍA: redesplegar (p. ej. para cambiar una variable) nunca debe borrar
# reservas reales. Para forzar la restauración a propósito: RESTAURAR=1 bash infra/azure/desplegar-azure.sh
FILAS=$(kubectl -n comedor exec $PG -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from reservas" 2>/dev/null' || true)
FILAS=${FILAS//[^0-9]/}
if [ "${FILAS:-0}" -gt 0 ] && [ "${RESTAURAR:-}" != "1" ]; then
  echo "La base ya tiene $FILAS reservas: NO se restaura el respaldo (forzar con RESTAURAR=1)."
else
  kubectl -n comedor exec $PG -- sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"' >/dev/null 2>&1 || true
  kubectl -n comedor exec -i $PG -- sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' < respaldo/comensales_reservas.sql >/dev/null 2>&1 || true
fi
kubectl -n comedor exec $PG -- sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select string_agg(relname||chr(61)||n_live_tup, chr(32)) from pg_stat_user_tables"'
kubectl -n comedor rollout restart deploy/comensales-reservas-service
kubectl -n comedor rollout status deploy/comensales-reservas-service --timeout=300s
kubectl -n comedor get svc comensales-reservas-service
