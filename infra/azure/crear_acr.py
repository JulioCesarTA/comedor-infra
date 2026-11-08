"""Crea el Azure Container Registry en comedor-azure, lo conecta al clúster AKS (rol AcrPull) y guarda sus credenciales de subida.

Uso (desde comedor-infra):  set -a; . ./respaldo/azure.env; set +a; python infra/azure/crear_acr.py
Escribe respaldo/acr.env con ACR_SERVIDOR, ACR_USUARIO y ACR_CLAVE (no se sube a git).
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

T = os.environ
SUB, GRUPO, AKS = T["AZURE_SUBSCRIPTION_ID"], T["AZURE_RESOURCE_GROUP"], T["AZURE_AKS_CLUSTER"]
ARM = "https://management.azure.com"


def llamar(metodo, url, cuerpo=None, token=None):
    datos = None if cuerpo is None else (json.dumps(cuerpo).encode() if not isinstance(cuerpo, bytes) else cuerpo)
    req = urllib.request.Request(url, datos, method=metodo, headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            texto = r.read().decode()
            return json.loads(texto) if texto else {}
    except urllib.error.HTTPError as e:
        raise SystemExit(f"{metodo} {url.split('?')[0].replace(ARM, '')} -> {e.code} {e.read().decode()[:400]}")


datos = urllib.parse.urlencode({"grant_type": "client_credentials", "client_id": T["AZURE_CLIENT_ID"], "client_secret": T["AZURE_CLIENT_SECRET"],
                                "scope": ARM + "/.default"}).encode()
token = json.load(urllib.request.urlopen(urllib.request.Request(f"https://login.microsoftonline.com/{T['AZURE_TENANT_ID']}/oauth2/v2.0/token", datos), timeout=30))["access_token"]

# 1. proveedor de registros (si la suscripción no lo tiene registrado)
estado = llamar("GET", f"{ARM}/subscriptions/{SUB}/providers/Microsoft.ContainerRegistry?api-version=2021-04-01", token=token).get("registrationState")
print("proveedor Microsoft.ContainerRegistry:", estado)
if estado != "Registered":
    llamar("POST", f"{ARM}/subscriptions/{SUB}/providers/Microsoft.ContainerRegistry/register?api-version=2021-04-01", b"", token)
    for _ in range(30):
        time.sleep(5)
        if llamar("GET", f"{ARM}/subscriptions/{SUB}/providers/Microsoft.ContainerRegistry?api-version=2021-04-01", token=token).get("registrationState") == "Registered":
            break

# 2. el registro (nombre estable derivado de la suscripción)
nombre = "comedorreg" + SUB.replace("-", "")[:8]
base = f"{ARM}/subscriptions/{SUB}/resourceGroups/{GRUPO}/providers/Microsoft.ContainerRegistry/registries/{nombre}"
llamar("PUT", base + "?api-version=2023-07-01", {"location": "centralus", "sku": {"name": "Basic"}, "properties": {"adminUserEnabled": True}}, token)
for _ in range(40):
    r = llamar("GET", base + "?api-version=2023-07-01", token=token)
    if r["properties"].get("provisioningState") == "Succeeded":
        break
    time.sleep(5)
servidor = r["properties"]["loginServer"]
print("registro:", servidor)

# 3. el clúster podrá bajar imágenes sin credenciales (AcrPull a la identidad de los nodos)
aks = llamar("GET", f"{ARM}/subscriptions/{SUB}/resourceGroups/{GRUPO}/providers/Microsoft.ContainerService/managedClusters/{AKS}?api-version=2024-05-01", token=token)
kubelet = aks["properties"]["identityProfile"]["kubeletidentity"]["objectId"]
rol = f"/subscriptions/{SUB}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"   # AcrPull
asignacion = str(uuid.uuid5(uuid.NAMESPACE_URL, f"{nombre}-{kubelet}-acrpull"))
try:
    llamar("PUT", f"{ARM}{r['id']}/providers/Microsoft.Authorization/roleAssignments/{asignacion}?api-version=2022-04-01",
           {"properties": {"roleDefinitionId": rol, "principalId": kubelet, "principalType": "ServicePrincipal"}}, token)
    print("AcrPull concedido a los nodos de", AKS)
except SystemExit as e:
    print("AcrPull:", str(e)[:200])

# 4. credenciales para subir imágenes desde el PC
c = llamar("POST", base + "/listCredentials?api-version=2023-07-01", b"", token)
with open("respaldo/acr.env", "w", encoding="utf8", newline="\n") as f:
    f.write(f"ACR_SERVIDOR={servidor}\nACR_USUARIO={c['username']}\nACR_CLAVE={c['passwords'][0]['value']}\n")
print("credenciales guardadas en respaldo/acr.env")
