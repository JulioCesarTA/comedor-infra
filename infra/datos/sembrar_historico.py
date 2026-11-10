#!/usr/bin/env python3
"""Siembra historial de demostración (menús, reservas, pagos, estudiantes y becas) en las 3 nubes.

Qué crea (todo es AGREGADO; con --rehacer primero borra lo sembrado antes):
  - Mongo  (AWS EKS)   : menús 'hist-AAAAMMDD-T' con cupo y porciones apartadas   -> colección menus
  - Postgres (Azure)   : estudiantes (registro 23xxxxx), becas, reservas           -> menuId empieza con 'hist-'
  - Postgres (GCP)     : pagos y tickets de esas reservas                          -> reserva_id = id de la reserva sembrada

Tamaño (pensado para el modelo de demanda, que pide 2.000 registros fecha × turno × plato):
  - 22 meses de menús (1/1/2025 → 31/10/2026): ~2.100 registros, con la escala real del comedor
    (cupo 120 desayuno / 180 almuerzo / 120 cena, demanda típica 50-150 raciones por plato).
  - Reservas, pagos y tickets fila por fila SOLO de los últimos 60 días del historial (~17 mil filas).
    El modelo entrena con las porciones apartadas de los menús, no con las reservas; sembrar las reservas de
    los 22 meses serían ~180 mil filas y los reportes (que bajan todas las reservas) dejarían de servir.
La demanda tiene patrón real (día de la semana, turno, popularidad del plato, feriados, exámenes, vacaciones, temperatura
y tendencia) para que los modelos tengan algo que aprender.

Uso (Git Bash, desde comedor-infra):
    python infra/datos/sembrar_historico.py --seco       # solo genera y muestra conteos (no toca ninguna nube)
    python infra/datos/sembrar_historico.py              # genera y carga en las 3 nubes (falla si ya hay datos sembrados)
    python infra/datos/sembrar_historico.py --rehacer    # borra lo sembrado antes ('hist-', registro 23xxxxx) y vuelve a cargar
"""
import argparse
import csv
import importlib.util
import io
import json
import os
import subprocess
import sys
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from urllib.request import urlopen

import numpy as np

RAIZ = Path(__file__).resolve().parents[2]            # comedor-infra
REPOS = RAIZ.parent
HOY = date.today()
FIN_HIST = date(2026, 10, 31)                         # lo que ya existía en las bases empieza el 2/11/2026
INICIO = date(2025, 1, 1)                             # 22 meses -> ~2.100 registros fecha × turno × plato
DIAS_CON_RESERVAS = 60                                # solo estos últimos días llevan reservas/pagos fila por fila
DESDE_RESERVAS = FIN_HIST - timedelta(days=DIAS_CON_RESERVAS - 1)
ESTUDIANTES_NUEVOS = 400                              # alcanza para llenar un cupo de 180 sin repetir estudiante
rng = np.random.default_rng(42)

# ---------------------------------------------------------------- calendario (el mismo que usa el modelo)
_spec = importlib.util.spec_from_file_location("calendario", REPOS / "ia-ml-service/app/domain/analitica/calendario.py")
cal = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(cal)


def en_periodo(d: date, periodos) -> bool:
    return any(a <= d <= b for a, b in periodos)


# ---------------------------------------------------------------- platos: (id, popularidad, es_sopa)
ALMUERZO = [("arroz-con-pollo", 1.35, 0), ("asado-de-res", 1.25, 0), ("majadito", 1.15, 0), ("milanesa", 1.20, 0),
            ("silpancho", 1.10, 0), ("pique-macho", 0.95, 0), ("charque", 0.90, 0), ("fricase", 0.85, 0),
            ("tallarin-con-carne", 0.80, 0), ("chicharron", 0.75, 0), ("locro", 0.65, 1), ("sopa-de-mani", 0.55, 1)]
DESAYUNO = [("api-con-pastel", 1.25, 1), ("pan-con-leche", 1.0, 0), ("sonso", 0.8, 0), ("cunape-con-api", 0.7, 1)]
CENA = [("sopa-de-fideo", 1.0, 1), ("arroz-con-queso", 1.1, 0), ("tortilla-de-papa", 0.85, 0), ("pollo-frito", 1.25, 0)]
TURNOS = {  # demanda base por plato (raciones), cupo por plato, precio Bs, hora UTC del cobro
    "DESAYUNO": dict(platos=DESAYUNO, n=1, base=70.0, cupo=120, precio=6.0, hora=11),
    "ALMUERZO": dict(platos=ALMUERZO, n=2, base=95.0, cupo=180, precio=12.0, hora=16),
    "CENA": dict(platos=CENA, n=1, base=60.0, cupo=120, precio=10.0, hora=23),
}
FACTOR_DIA = (1.20, 1.20, 1.10, 1.00, 0.80, 0.45)    # lun..sáb

NOMBRES = ["Alejandro", "Camila", "Diego", "Valentina", "Mateo", "Sofía", "Sebastián", "Lucía", "Daniel", "Mariana", "Gabriel", "Paola",
           "Rodrigo", "Fernanda", "Andrés", "Daniela", "Marcelo", "Carla", "Jorge", "Natalia", "Luis", "Andrea", "Pablo", "Julieta"]
APELLIDOS = ["Rojas", "Vaca", "Suárez", "Terrazas", "Roca", "Montaño", "Justiniano", "Parada", "Peña", "Egüez", "Salvatierra", "Moreno",
             "Cuéllar", "Hurtado", "Áñez", "Barba", "Chávez", "Soliz", "Mercado", "Flores", "Ribera", "Arteaga", "Banzer", "Dorado"]


# ---------------------------------------------------------------- utilidades de entorno / kubectl
def env_archivo(nombre: str) -> dict:
    d = {}
    for linea in (RAIZ / nombre).read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def correr(cmd, entrada: bytes | None = None, env=None, comprobar=True):
    r = subprocess.run(cmd, input=entrada, capture_output=True, env={**os.environ, **(env or {})})
    if comprobar and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd[:6])}… falló:\n{r.stderr.decode('utf-8', 'replace')[-600:]}")
    return r.stdout.decode("utf-8", "replace")


def kube_aws():
    e = env_archivo(".env.cloud.nuevo")
    entorno = {k: v for k, v in e.items() if k.startswith("AWS_")}
    correr(["aws", "eks", "update-kubeconfig", "--region", "us-west-2", "--name", "comedor"], env=entorno)
    return ["kubectl", "-n", "comedor"], entorno


def kube_azure():
    return ["kubectl", "-n", "comedor"], {"KUBECONFIG": str((RAIZ / "respaldo/kube-aks.yaml").resolve())}


def kube_gcp():
    env = {"CLOUDSDK_CONFIG": os.path.join(os.environ.get("TEMP", "/tmp"), "gcloud-comedor"),
           "KUBECONFIG": os.path.join(os.environ.get("TEMP", "/tmp"), "kube-gke.yaml")}
    ps = lambda c: correr(["powershell", "-NoProfile", "-Command", c], env=env)
    ps(f"gcloud auth activate-service-account --key-file='{RAIZ / 'respaldo/gcp.json'}' 2>&1 | Out-Null")
    ps("gcloud container clusters get-credentials comedor-gke --zone us-central1-a --project comedor-universitario-514103 2>&1 | Out-Null")
    tok = ps("gcloud auth print-access-token 2>$null").strip()
    return ["kubectl", f"--token={tok}", "-n", "comedor"], env


def secreto(kube, nombre, clave):
    base, env = kube
    j = json.loads(correr(base + ["get", "secret", nombre, "-o", "json"], env=env))
    import base64
    return base64.b64decode(j["data"][clave]).decode()


def psql(kube, deploy, usuario, bd, sql=None, copia=None):
    """Ejecuta SQL (-c) y, si hay `copia`, envía esos datos CSV por stdin a un \\copy ... from stdin."""
    base, env = kube
    cmd = base + ["exec", "-i", f"deploy/{deploy}", "--", "psql", "-U", usuario, "-d", bd, "-v", "ON_ERROR_STOP=1", "-At", "-c", sql]
    return correr(cmd, entrada=copia.encode("utf-8") if copia else None, env=env)


def mongosh(kube, js: str) -> str:
    e = env_archivo(".env")
    base, env = kube
    return correr(base + ["exec", "-i", "deploy/mongo", "--", "mongosh", "--quiet", "-u", e["MONGO_INITDB_ROOT_USERNAME"], "-p",
                          e["MONGO_INITDB_ROOT_PASSWORD"], "--authenticationDatabase", "admin", e.get("MONGO_DB_MENU", "menu_inventario")],
                  entrada=js.encode("utf-8"), env=env)


# ---------------------------------------------------------------- temperatura real de Santa Cruz (con internet) o estacional
def temperaturas() -> dict[str, float]:
    try:
        url = ("https://archive-api.open-meteo.com/v1/archive?latitude=-17.78&longitude=-63.18&daily=temperature_2m_mean"
               f"&start_date={INICIO.isoformat()}&end_date={FIN_HIST.isoformat()}&timezone=America%2FLa_Paz")
        d = json.load(urlopen(url, timeout=25))["daily"]
        out = {f: t for f, t in zip(d["time"], d["temperature_2m_mean"]) if t is not None}
        print(f"  clima real: {len(out)} días")
        return out
    except Exception as e:
        print(f"  sin internet para el clima ({str(e)[:50]}): se usa una curva estacional")
        return {}


def temp_de(d: date, real: dict) -> float:
    t = real.get(d.isoformat())
    if t is not None:
        return float(t)
    return 24.5 + 5.5 * np.cos(2 * np.pi * (d.timetuple().tm_yday - 15) / 365.25) + float(rng.normal(0, 1.5))


# ---------------------------------------------------------------- generación
def generar_estudiantes():
    """Estudiantes nuevos (registro 23xxxxx); ~25 % becarios."""
    nuevos, becas = [], []
    for i in range(1, ESTUDIANTES_NUEVOS + 1):
        reg = f"23{i:05d}"
        nom = f"{NOMBRES[(i * 7) % len(NOMBRES)]} {APELLIDOS[(i * 11) % len(APELLIDOS)]} {APELLIDOS[(i * 5 + 3) % len(APELLIDOS)]}"
        nuevos.append(dict(id=str(uuid.uuid4()), reg=reg, nombre=nom, email=f"{reg}@uagrm.edu.bo", tel=f"+591 7{rng.integers(1000000, 9999999)}"))
    becarios = {n["id"] for n in nuevos[::4]}
    for n in nuevos[::4]:
        tipo, cupo = [("completa", 60), ("media", 40), ("parcial", 20)][int(rng.integers(0, 3))]
        becas.append(dict(id=str(uuid.uuid4()), est=n["id"], tipo=tipo, cupo=cupo, usadas=int(rng.integers(0, 4)),
                          desde="2025-01-01 00:00:00", hasta="2026-12-31 23:59:59"))
    return nuevos, becas, becarios


def generar_menus_y_reservas(est_ids: list[str], becarios: set[str], real_temp: dict):
    peso = rng.lognormal(0, 0.9, len(est_ids))
    peso /= peso.sum()
    menus, reservas, pagos, tickets = [], [], [], []
    dias_total = (FIN_HIST - INICIO).days
    ultimo = {}
    d = INICIO
    while d <= FIN_HIST:
        if d.weekday() == 6 or d in cal.FERIADOS:
            d += timedelta(days=1); continue
        vacacion = en_periodo(d, cal.PERIODOS_VACACIONES)
        examenes = en_periodo(d, cal.PERIODOS_EXAMENES)
        tendencia = 0.85 + 0.25 * ((d - INICIO).days / dias_total)             # el comedor crece con el tiempo
        temp = temp_de(d, real_temp)
        con_reservas = d >= DESDE_RESERVAS
        for turno, cfg in TURNOS.items():
            if vacacion and turno == "CENA":
                continue
            platos = cfg["platos"]
            pesos = np.array([p[1] for p in platos], dtype=float)
            for i, (pid, pop, sopa) in enumerate(platos):
                if ultimo.get((turno, pid)) == d - timedelta(days=1):         # no repetir el mismo plato dos días seguidos
                    pesos[i] *= 0.15
            elegidos = rng.choice(len(platos), size=min(cfg["n"], len(platos)), replace=False, p=pesos / pesos.sum())
            porciones = {}
            for idx in elegidos:
                pid, pop, sopa = platos[idx]
                ultimo[(turno, pid)] = d
                efecto_temp = 1 + 0.035 * (22 - temp) if sopa else 1 - 0.012 * (temp - 22)
                lam = (cfg["base"] * pop * FACTOR_DIA[d.weekday()] * tendencia * max(0.4, efecto_temp)
                       * (0.40 if vacacion else 1.0) * (1.25 if examenes else 1.0) * float(rng.lognormal(0, 0.12)))
                apartadas = int(min(cfg["cupo"], rng.poisson(lam)))
                porciones[f"plato-{pid}"] = dict(platoId=f"plato-{pid}", cupoTotal=cfg["cupo"], apartadas=apartadas)
                if not con_reservas:
                    continue
                # reservas: `apartadas` vigentes (consumidas o no vino) + ~12% canceladas (ya liberadas)
                n_canc = int(rng.binomial(max(apartadas, 1), 0.12)) if apartadas else 0
                n_total = apartadas + n_canc
                if n_total:
                    quien = rng.choice(len(est_ids), size=min(n_total, len(est_ids)), replace=False, p=peso)
                    for j, e in enumerate(quien):
                        cancelada = j >= apartadas
                        rid = str(uuid.uuid4())
                        creada = datetime(d.year, d.month, d.day, 12) - timedelta(hours=float(rng.uniform(2, 40)))
                        estado = "cancelada" if cancelada else ("consumida" if rng.random() < 0.92 else "confirmada")
                        mid = f"hist-{d:%Y%m%d}-{turno[0]}"
                        reservas.append((rid, est_ids[e], mid, f"plato-{pid}", d.isoformat(), turno, estado, creada.strftime("%Y-%m-%d %H:%M:%S")))
                        # pago: becarios no pagan; los demás efectivo o QR. Las canceladas pagadas se devolvieron.
                        if cancelada and rng.random() < 0.3:
                            continue                                           # canceló antes de pagar
                        metodo = "beca" if (est_ids[e] in becarios and rng.random() < 0.9) else ("efectivo" if rng.random() < 0.4 else "qr_bancario")
                        monto = 0.0 if metodo == "beca" else cfg["precio"]
                        pid_pago, tid = str(uuid.uuid4()), str(uuid.uuid4())
                        emitido = datetime(d.year, d.month, d.day, cfg["hora"], int(rng.integers(0, 59)), int(rng.integers(0, 59))).replace(tzinfo=timezone.utc)
                        pagos.append((pid_pago, rid, est_ids[e], f"{monto:.2f}", metodo, "devuelto" if cancelada else "cobrado", tid, emitido.isoformat()))
                        tickets.append((tid, pid_pago, rid, f"{monto:.2f}", emitido.isoformat()))
            menus.append(dict(_id=f"hist-{d:%Y%m%d}-{turno[0]}", fecha=d.isoformat(), turno=turno, publicado=True, porciones=porciones))
        d += timedelta(days=1)
    # próxima semana publicada (sin reservas) para que el portal y el planificador tengan menús futuros
    d = date(2026, 11, 9)
    while d <= date(2026, 11, 14):
        for turno, cfg in TURNOS.items():
            pl = cfg["platos"]
            elegidos = rng.choice(len(pl), size=min(cfg["n"], len(pl)), replace=False)
            menus.append(dict(_id=f"hist-{d:%Y%m%d}-{turno[0]}", fecha=d.isoformat(), turno=turno, publicado=True,
                              porciones={f"plato-{pl[i][0]}": dict(platoId=f"plato-{pl[i][0]}", cupoTotal=cfg["cupo"], apartadas=0) for i in elegidos}))
        d += timedelta(days=1)
    return menus, reservas, pagos, tickets


def csv_texto(filas) -> str:
    b = io.StringIO()
    csv.writer(b, lineterminator="\n").writerows(filas)
    return b.getvalue()


def resumen(menus, reservas, pagos, tickets, nuevos, becas, existentes=0):
    pasadas = [p for m in menus if m["fecha"] <= FIN_HIST.isoformat() for p in m["porciones"].values()]
    ap = np.array([p["apartadas"] for p in pasadas])
    cupos = np.array([p["cupoTotal"] for p in pasadas])
    print(f"  estudiantes nuevos {len(nuevos)} (+{existentes} existentes) · becas {len(becas)}")
    print(f"  menús {len(menus)} · registros fecha×turno×plato pasados {len(pasadas)} (el modelo pide 2.000)")
    print(f"  apartadas por plato: media {ap.mean():.0f} · mediana {np.median(ap):.0f} · máx {ap.max()} · "
          f"ocupación media {100 * ap.sum() / cupos.sum():.0f} % · agotados {int((ap == cupos).sum())}")
    print(f"  reservas {len(reservas)} (desde {DESDE_RESERVAS}) · pagos {len(pagos)} · tickets {len(tickets)}")


# ---------------------------------------------------------------- borrar lo sembrado antes
def deshacer(aws, azure, gcp, dbu, gu):
    print("Borrando lo sembrado antes…")
    print("  Mongo:", mongosh(aws, "const r=db.menus.deleteMany({_id:/^hist-/});print('menús borrados '+r.deletedCount)").strip().splitlines()[-1])
    print("  Azure reservas:", psql(azure, "postgres-comensales", dbu, "comensales_reservas",
                                    "delete from reservas where \"menuId\" like 'hist-%'").strip())
    print("  Azure becas:", psql(azure, "postgres-comensales", dbu, "comensales_reservas",
                                 "delete from becas where \"estudianteId\" in (select id from estudiantes where \"registroUniv\" like '23%')").strip())
    print("  Azure estudiantes:", psql(azure, "postgres-comensales", dbu, "comensales_reservas",
                                       "delete from estudiantes where \"registroUniv\" like '23%'").strip())
    # Lo real en pagos empieza el 2/11/2026: todo lo anterior es sembrado
    print("  GCP tickets:", psql(gcp, "postgres-pagos", gu, "pagos_tickets",
                                 "delete from tickets where pago_id in (select id from pagos where created_at < '2026-11-01')").strip())
    print("  GCP pagos:", psql(gcp, "postgres-pagos", gu, "pagos_tickets", "delete from pagos where created_at < '2026-11-01'").strip())


# ---------------------------------------------------------------- carga
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seco", action="store_true", help="solo genera y muestra conteos (no toca ninguna nube)")
    ap.add_argument("--rehacer", action="store_true", help="borra lo sembrado antes y vuelve a cargar")
    args = ap.parse_args()

    print("Generando…")
    real = temperaturas()
    nuevos, becas, becarios = generar_estudiantes()

    if args.seco:
        menus, reservas, pagos, tickets = generar_menus_y_reservas([n["id"] for n in nuevos], becarios, real)
        resumen(menus, reservas, pagos, tickets, nuevos, becas)
        return

    aws, azure, gcp = kube_aws(), kube_azure(), kube_gcp()
    dbu = secreto(azure, "comensales-secretos", "db-user")
    gu = secreto(gcp, "pagos-secretos", "db-user")
    ya = psql(azure, "postgres-comensales", dbu, "comensales_reservas", "select count(*) from reservas where \"menuId\" like 'hist-%'").strip()
    if ya != "0":
        if not args.rehacer:
            sys.exit(f"Ya hay {ya} reservas sembradas ('hist-'). Para reemplazarlas corre con --rehacer.")
        deshacer(aws, azure, gcp, dbu, gu)

    existentes = [l.strip() for l in psql(azure, "postgres-comensales", dbu, "comensales_reservas", "select id from estudiantes").splitlines() if l.strip()]
    est_ids = existentes + [n["id"] for n in nuevos]
    menus, reservas, pagos, tickets = generar_menus_y_reservas(est_ids, becarios, real)
    resumen(menus, reservas, pagos, tickets, nuevos, becas, len(existentes))

    # ---- Mongo (AWS)
    print("Cargando menús en Mongo (AWS)…")
    for i in range(0, len(menus), 400):
        docs = []
        for m in menus[i:i + 400]:
            docs.append(dict(_id=m["_id"], fecha={"$date": m["fecha"] + "T00:00:00Z"}, turno=m["turno"], publicado=True,
                             porciones=m["porciones"], _class="com.uagrm.comedor.menu.domain.model.Menu"))
        js = "const L=" + json.dumps(docs) + ";L.forEach(d=>{d.fecha=new Date(d.fecha.$date)});db.menus.insertMany(L);print('ok '+L.length)"
        print("  ", mongosh(aws, js).strip().splitlines()[-1])

    # ---- Postgres Azure
    print("Cargando estudiantes, becas y reservas en Postgres (Azure)…")
    psql(azure, "postgres-comensales", dbu, "comensales_reservas",
         "\\copy estudiantes (id,\"registroUniv\",nombre,email,telefono) from stdin csv",
         csv_texto([(n["id"], n["reg"], n["nombre"], n["email"], n["tel"]) for n in nuevos]))
    psql(azure, "postgres-comensales", dbu, "comensales_reservas",
         "\\copy becas (id,\"estudianteId\",tipo,\"cupoRacionesMes\",\"racionesUsadasMes\",\"vigenteDesde\",\"vigenteHasta\") from stdin csv",
         csv_texto([(b["id"], b["est"], b["tipo"], b["cupo"], b["usadas"], b["desde"], b["hasta"]) for b in becas]))
    psql(azure, "postgres-comensales", dbu, "comensales_reservas",
         "\\copy reservas (id,\"estudianteId\",\"menuId\",\"platoId\",fecha,turno,estado,\"createdAt\") from stdin csv", csv_texto(reservas))

    # ---- Postgres GCP
    print("Cargando pagos y tickets en Postgres (GCP)…")
    psql(gcp, "postgres-pagos", gu, "pagos_tickets",
         "\\copy pagos (id,reserva_id,estudiante_id,monto,metodo,estado,ticket_id,created_at) from stdin csv", csv_texto(pagos))
    psql(gcp, "postgres-pagos", gu, "pagos_tickets",
         "\\copy tickets (id,pago_id,reserva_id,monto,emitido_en) from stdin csv", csv_texto(tickets))
    print("Listo.")


if __name__ == "__main__":
    main()

# DESHACER a mano (es lo mismo que hace --rehacer antes de cargar):
#   Mongo   : db.menus.deleteMany({_id: /^hist-/})
#   Azure   : delete from reservas where "menuId" like 'hist-%';
#             delete from becas where "estudianteId" in (select id from estudiantes where "registroUniv" like '23%');
#             delete from estudiantes where "registroUniv" like '23%';
#   GCP     : delete from tickets where pago_id in (select id from pagos where created_at < '2026-11-01');
#             delete from pagos where created_at < '2026-11-01';
