"""Realm de Keycloak para la EC2: el realm exportado (respaldo/keycloak-realm.json) con las URL https del servidor.

Uso: python infra/ec2/realm.py <HOST sslip.io> <salida.json>
"""
import json
import sys

host, salida = sys.argv[1:3]
realm = json.load(open("respaldo/keycloak-realm.json", encoding="utf8"))
for c in realm["clients"]:
    if c["clientId"] in ("shell", "portal-estudiante", "backoffice-gestion", "inteligencia-negocio", "app-movil", "api-gateway"):
        https = [f"https://{host}/*"] + [f"https://{host}:{p}/*" for p in (3001, 3002, 3003)]
        c["redirectUris"] = sorted(set([u for u in c.get("redirectUris", []) if "sslip.io" not in u and "32.187" not in u] + https))
        orig = [f"https://{host}"] + [f"https://{host}:{p}" for p in (3001, 3002, 3003)]
        c["webOrigins"] = sorted(set([o for o in c.get("webOrigins", []) if "sslip.io" not in o and "32.187" not in o] + orig))
realm["sslRequired"] = "none"
json.dump(realm, open(salida, "w", encoding="utf8"), ensure_ascii=False)
print("realm listo:", len(realm["users"]), "usuarios")
