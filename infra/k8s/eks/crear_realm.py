"""Arma el realm de Keycloak para la cuenta nueva: realm vivo exportado (clientes y roles) + usuarios.

Uso: python infra/k8s/eks/crear_realm.py <realm-vivo.json> <usuarios-vivos.json> <host-publico> <salida.json>
Las cuentas demo conservan la contraseña del realm del repo (auth/keycloak/comedor-realm.json);
las demás se crean con la contraseña inicial "Cambiar123!" (temporal: Keycloak pide cambiarla al entrar).
"""
import json
import sys

vivo, usuarios, host, salida = sys.argv[1:5]
realm = json.load(open(vivo, encoding="utf8"))
base = {u["username"]: u for u in json.load(open("auth/keycloak/comedor-realm.json", encoding="utf8"))["users"]}

puertos = [3000, 3001, 3002, 3003]
for c in realm.get("clients", []):
    if c["clientId"] in ("shell", "portal-estudiante", "backoffice-gestion", "inteligencia-negocio", "app-movil", "api-gateway"):
        uris = [u for u in c.get("redirectUris", []) if "44.252.104.3" not in u]
        uris += [f"http://{host}:{p}/*" for p in puertos]
        c["redirectUris"] = sorted(set(uris))
        origins = [o for o in c.get("webOrigins", []) if "44.252.104.3" not in o]
        c["webOrigins"] = sorted(set(origins + [f"http://{host}:{p}" for p in puertos]))

lista = []
for u in json.load(open(usuarios, encoding="utf8")):
    roles = [r for r in u.pop("roles") if not r.startswith("default-roles")]
    nuevo = {k: v for k, v in u.items() if v is not None}
    nuevo["realmRoles"] = roles
    if u["username"] in base:
        nuevo["credentials"] = base[u["username"]]["credentials"]
    else:
        nuevo["credentials"] = [{"type": "password", "value": "Cambiar123!", "temporary": True}]
    lista.append(nuevo)
realm["users"] = lista
realm["sslRequired"] = "none"
json.dump(realm, open(salida, "w", encoding="utf8"), ensure_ascii=False)
print(len(lista), "usuarios;", len(realm["clients"]), "clientes")
