# Despliega pagos-tickets-service (con su Postgres) en el clúster GKE "comedor-gke" (GCP).
# Requiere: respaldo\gcp.json (cuenta de servicio), .env, .env.secrets, .env.cloud.nuevo (EKS_EDGE_IP), respaldo\pagos_tickets.sql
# Uso (PowerShell, desde la raíz de comedor-infra):  .\infra\gcp\desplegar-gcp.ps1
$ErrorActionPreference = "Continue"   # gcloud escribe avisos en stderr
$env:CLOUDSDK_CONFIG = Join-Path $env:TEMP "gcloud-comedor"
$env:KUBECONFIG = Join-Path $env:TEMP "kube-gke.yaml"
$P = "comedor-universitario-514103"

function Leer($archivo, $clave) { (Select-String -Path $archivo -Pattern "^$clave=" | Select-Object -First 1).Line.Substring($clave.Length + 1) }

gcloud auth activate-service-account --key-file=respaldo\gcp.json 2>&1 | Out-Null
gcloud container clusters get-credentials comedor-gke --zone us-central1-a --project $P 2>&1 | Out-Null
$tok = gcloud auth print-access-token 2>$null          # sin el plugin gke-gcloud-auth-plugin: se usa el token directamente
function K { $input | kubectl --token=$tok @args }          # $input: lo que llega por tubería (kubectl apply -f -)

$appKey = ((Select-String -Path docker-compose.yml -Pattern "^\s+APP_KEY:").Line -replace '.*APP_KEY:\s*', '').Trim('"')
K -n comedor create secret generic pagos-secretos `
    --from-literal=db-user="$(Leer .env POSTGRES_PAGOS_USER)" --from-literal=db-pass="$(Leer .env POSTGRES_PAGOS_PASSWORD)" `
    --from-literal=app-key="$appKey" --from-literal=stripe="$(Leer .env.secrets STRIPE_SECRET_KEY)" `
    --dry-run=client -o yaml | K apply -f -

$edge = Leer .env.cloud.nuevo EKS_EDGE_IP
(Get-Content infra\k8s\gcp\pagos-tickets-service\pagos.yaml -Raw).Replace("__EKS_EDGE_IP__", $edge) | K apply -f -

K -n comedor rollout status deploy/postgres-pagos --timeout=300s
# datos: el respaldo solo se carga en una base VACÍA (redesplegar nunca debe borrar pagos reales).
# Para forzar la restauración a propósito: $env:RESTAURAR = "1" antes de correr el script.
# '--' va entre comillas: sin ellas PowerShell lo toma como fin de parámetros y no le llega a kubectl.
$pg = (K -n comedor get pod -l app=postgres-pagos -o name | Select-Object -First 1).Replace("pod/", "")
$filas = (K -n comedor exec $pg '--' sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select count(*) from pagos" 2>/dev/null') -replace '[^0-9]', ''
if ([int]("0" + $filas) -gt 0 -and $env:RESTAURAR -ne "1") {
    Write-Host "La base ya tiene $filas pagos: NO se restaura el respaldo (forzar con `$env:RESTAURAR = '1')."
} else {
    K -n comedor exec $pg '--' sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"' | Out-Null
    Get-Content respaldo\pagos_tickets.sql -Raw | K -n comedor exec -i $pg '--' sh -c 'psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB"' 2>&1 | Out-Null
}
K -n comedor rollout status deploy/pagos-tickets-service --timeout=300s
K -n comedor get svc pagos-tickets-service
