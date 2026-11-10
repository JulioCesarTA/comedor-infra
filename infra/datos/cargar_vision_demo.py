"""Demo de vision: carga fotos de bandejas en el pipeline REAL de vision de ia-ml (TensorFlow en el servidor, fotos en S3):
  1) referencias: una foto de bandeja llena por plato  -> POST /ml/vision/referencia
  2) bandejas: fotos reales parcialmente comidas + variantes sinteticas (se tapa parte de la comida con el color
     de la bandeja segun la mascara que devuelve el modelo) -> POST /ml/vision/bandeja (el modelo calcula el % restante)
Usa port-forward al pod de ia-ml (credenciales de .env.cloud.nuevo). Fotos: carpeta FOTOS_BANDEJAS
(por defecto ../pagos-tickets-service/im: 36 fotos de WhatsApp; ver MAPA para saber cual es cada plato).
Uso (desde comedor-infra):
    python infra/datos/cargar_vision_demo.py --seco    # muestra el mapeo foto -> plato y fechas
    python infra/datos/cargar_vision_demo.py           # referencias + 4 sinteticas por plato + bandejas reales
    python infra/datos/cargar_vision_demo.py --extra   # ademas 8 sinteticas mas por plato (distribucion realista)
    python infra/datos/cargar_vision_demo.py --rehacer --extra   # borra antes la demo anterior (no toca lo del celular)
    python infra/datos/cargar_vision_demo.py --plato plato-pollo-frito   # solo ese plato
    python infra/datos/cargar_vision_demo.py --pollo --rehacer   # SOLO la carpeta im/pollo: bandeja llena + 10 bandejas,
                                                                 # y compara cada sector con im/pollo/etiquetas.csv
"""
import io
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageFilter, ImageOps

RAIZ = Path(__file__).resolve().parents[2]            # comedor-infra
CARPETA_IM = Path(os.environ.get("FOTOS_BANDEJAS", RAIZ.parent / "pagos-tickets-service" / "im"))
IM = sorted(CARPETA_IM.glob("*.jpeg"))
SECO = "--seco" in sys.argv
PUERTO = 18080
API = f"http://localhost:{PUERTO}"

# plato del historial -> (indice de la foto llena = referencia, indices de fotos reales comidas, nombres de sectores).
# Cada bandeja comida se compara con la foto llena de SU MISMA bandeja (misma comida en el mismo compartimento); si un
# plato se sirvio en dos bandejas distintas, va una lista. Pollo: #19 (bandeja blanca) -> #27 ; #28 (beige) -> #31.
# Los nombres dicen como se llama cada sector en ese plato (la red reconoce arroz/ensalada/guarnicion/proteina/postre).
MAPA = {
    # Almuerzo
    "plato-milanesa":           (17, [30, 22, 34, 26], {"proteina": "milanesa", "guarnicion": "papas", "postre": "gelatina"}),
    "plato-asado-de-res":       (18, [32], {"proteina": "carne asada", "guarnicion": "papas", "postre": "gelatina"}),
    "plato-silpancho":          (20, [25], {"proteina": "carne", "guarnicion": "puré", "postre": "manzana"}),
    "plato-chicharron":         (29, [35], {"proteina": "cerdo", "guarnicion": "papas", "postre": "fruta"}),
    "plato-charque":            (21, [23], {"proteina": "pescado", "guarnicion": "yuca", "postre": "helado"}),
    "plato-tallarin-con-carne": (24, [], {"proteina": "albóndigas", "guarnicion": "tallarín", "postre": "jugo"}),
    "plato-pique-macho":        (5, [], {"proteina": "carne", "guarnicion": "puré", "postre": "pera"}),
    "plato-arroz-con-pollo":    (12, [], {"proteina": "pollo", "guarnicion": "frejol", "postre": "manzana"}),
    "plato-fricase":            (13, [], {"proteina": "cerdo", "guarnicion": "frejol", "postre": "manzana"}),
    "plato-majadito":           (9, [], {"proteina": "carne", "guarnicion": "papas", "postre": "helado"}),
    "plato-locro":              (10, [], {"proteina": "huevo", "guarnicion": "lentejas y plátano", "postre": "helado"}),
    "plato-sopa-de-mani":       (14, [], {"proteina": "tacos", "guarnicion": "sopa y frejol", "postre": "jugo"}),
    # Cena
    "plato-pollo-frito":        [(19, [27], {"proteina": "pollo", "guarnicion": "papas fritas", "postre": "naranja"}),
                                 (28, [31], {"proteina": "pollo", "guarnicion": "papas fritas", "postre": "fruta"})],
    "plato-sopa-de-fideo":      (1, [], {"guarnicion": "pan y tallarín", "ensalada": "ensalada y verduras", "postre": "gelatina"}),
    "plato-arroz-con-queso":    (16, [33], {"proteina": "pescado", "guarnicion": "yuca", "postre": "helado"}),
    "plato-tortilla-de-papa":   (0, [], {"proteina": "pescado", "guarnicion": "puré", "ensalada": "pepino", "postre": "naranja"}),
}
# fracciones de comida "comida" (quitada) para las bandejas sinteticas; el resto queda
COMIDO_SINTETICO = [0.20, 0.45, 0.70, 0.90]
# --extra: mas bandejas por plato con la distribucion real de un comedor (la mayoria casi termina el plato)
COMIDO_EXTRA = [0.97, 0.95, 0.93, 0.90, 0.88, 0.85, 0.80, 0.75]
EXTRA = "--extra" in sys.argv
SOLO = sys.argv[sys.argv.index("--plato") + 1] if "--plato" in sys.argv else None


REHACER = "--rehacer" in sys.argv


def pares():
    """[(plato, indice referencia, reales, nombres)] respetando --plato."""
    return [(p, i_ref, reales, nombres) for p, v in MAPA.items() if SOLO in (None, p)
            for i_ref, reales, nombres in (v if isinstance(v, list) else [v])]


def borrar_demo(platos: list[str]):
    """--rehacer: borra del pod las referencias y bandejas de la demo (origen servidor) de esos platos.
    Lo registrado desde el celular (origen movil) no se toca."""
    marcas = ",".join("?" * len(platos))
    py = ("import sqlite3,sys,json;p=json.loads(sys.argv[1]);c=sqlite3.connect('/data/agentes.db');"
          f"b=c.execute(\"DELETE FROM bandejas WHERE plato_id IN ({marcas}) AND COALESCE(origen,'servidor')='servidor'\",p).rowcount;"
          f"r=c.execute(\"DELETE FROM ref_porcion WHERE plato_id IN ({marcas}) AND COALESCE(origen,'servidor')='servidor'\",p).rowcount;"
          "c.commit();print(f'borradas {r} referencias y {b} bandejas')")
    print(correr(["kubectl", "-n", "comedor", "exec", "deploy/ia-ml-service", "--", "python", "-c", py, json.dumps(platos)], env=AWS).strip())


def env_archivo(nombre):
    d = {}
    for linea in (RAIZ / nombre).read_text(encoding="utf-8").splitlines():
        if "=" in linea and not linea.lstrip().startswith("#"):
            k, v = linea.split("=", 1)
            d[k.strip()] = v.strip()
    return d


def correr(cmd, entrada=None, env=None):
    r = subprocess.run(cmd, input=entrada, capture_output=True, env={**os.environ, **(env or {})})
    if r.returncode != 0:
        raise SystemExit(f"{cmd[:4]} fallo:\n{r.stderr.decode('utf-8', 'replace')[-800:]}")
    return r.stdout.decode("utf-8", "replace")


nube = env_archivo(".env.cloud.nuevo")
AWS = {k: v for k, v in nube.items() if k.startswith("AWS_")}
correr(["aws", "eks", "update-kubeconfig", "--region", "us-west-2", "--name", "comedor"], env=AWS)
e = env_archivo(".env")


def ultimo_servicio() -> dict[str, tuple[str, str]]:
    """{platoId: (fecha, turno)} del ultimo dia servido (menus hist, hasta ayer)."""
    js = r"""
const hoy = new Date(); hoy.setUTCHours(0,0,0,0);
const r = db.menus.aggregate([{$match: {_id: /^hist-/, fecha: {$lt: hoy}}}, {$project: {fecha: 1, turno: 1, p: {$objectToArray: "$porciones"}}}, {$unwind: "$p"},
  {$sort: {fecha: -1}}, {$group: {_id: "$p.v.platoId", fecha: {$first: "$fecha"}, turno: {$first: "$turno"}}}]).toArray();
print(JSON.stringify(r.map(x => [x._id, x.fecha.toISOString().slice(0,10), x.turno])));
"""
    out = correr(["kubectl", "-n", "comedor", "exec", "-i", "deploy/mongo", "--", "mongosh", "--quiet", "-u", e["MONGO_INITDB_ROOT_USERNAME"],
                  "-p", e["MONGO_INITDB_ROOT_PASSWORD"], "--authenticationDatabase", "admin", e.get("MONGO_DB_MENU", "menu_inventario")],
                 entrada=js.encode(), env=AWS)
    out = out.replace("menu_inventario> ", "")
    linea = [l for l in out.splitlines() if l.strip().startswith("[")][-1]
    return {p: (f, t) for p, f, t in json.loads(linea)}


def jpeg(img: Image.Image, calidad=88) -> bytes:
    b = io.BytesIO()
    img.save(b, format="JPEG", quality=calidad)
    return b.getvalue()


def abrir(i: int) -> Image.Image:
    return ImageOps.exif_transpose(Image.open(IM[i])).convert("RGB")


def bandeja_sintetica(img: Image.Image, mascara: list, comido: float, semilla: int) -> Image.Image:
    """Tapa una fraccion `comido` de las zonas de comida (mascara 56x56 del modelo) con el color de la bandeja,
    "comiendo" desde un borde elegido al azar, con borde suave y algunas migas."""
    rng = np.random.default_rng(semilla)
    m = np.array(mascara, dtype=bool)                      # 56x56
    rej = m.shape[0]
    W, H = img.size
    arr = np.asarray(img).astype(np.float32)
    # color de bandeja: mediana de los pixeles que NO son comida
    no_comida = np.kron(~m, np.ones((H // rej + 1, W // rej + 1), dtype=bool))[:H, :W]
    fondo = np.median(arr[no_comida], axis=0) if no_comida.any() else np.array([225, 220, 210], dtype=np.float32)
    # orden de "comida": por distancia a un punto de arranque (un borde/esquina al azar)
    ys, xs = np.nonzero(m)
    if len(ys) == 0:
        return img
    y0, x0 = rng.choice([0, rej - 1]), rng.choice([0, rej - 1])
    orden = np.argsort((ys - y0) ** 2 + (xs - x0) ** 2 + rng.normal(0, 40, len(ys)))
    n = int(round(comido * len(ys)))
    quitar = np.zeros_like(m)
    quitar[ys[orden[:n]], xs[orden[:n]]] = True
    # mascara a tamaño de imagen, con borde suave
    mk = Image.fromarray((quitar * 255).astype(np.uint8)).resize((W, H), Image.BILINEAR).filter(ImageFilter.GaussianBlur(max(2, W // 150)))
    alfa = (np.asarray(mk).astype(np.float32) / 255.0)[..., None]
    relleno = np.empty_like(arr)
    relleno[...] = fondo + rng.normal(0, 3, arr.shape)      # bandeja con un poco de ruido
    # migas: puntitos del color original en el 2 % de la zona tapada
    migas = (rng.random((H, W)) < 0.02)[..., None] & (alfa > 0.6)
    salida = arr * (1 - alfa) + relleno * alfa
    salida = np.where(migas, arr * 0.8 + relleno * 0.2, salida)
    return Image.fromarray(np.clip(salida, 0, 255).astype(np.uint8))


def esperar_api(pf):
    for _ in range(40):
        try:
            requests.get(f"{API}/health", timeout=3); return
        except Exception:
            time.sleep(1)
    pf.terminate(); raise SystemExit("ia-ml no responde por el port-forward")


def texto_sectores(b: dict) -> str:
    return " · ".join(f"{s['nombre']} {s['restante']:.0f}%" for s in b.get("sectores") or []) or "(sin sectores)"


def pollo():
    """Demo del pollo: la bandeja llena y las 10 bandejas de im/pollo, comparando cada sector con etiquetas.csv."""
    import csv
    carpeta, plato = CARPETA_IM / "pollo", "plato-pollo-frito"
    fecha, turno = ultimo_servicio().get(plato, ("2026-11-09", "CENA"))
    if REHACER:
        borrar_demo([plato])
    verdad = {r["archivo"]: r for r in csv.DictReader(open(carpeta / "etiquetas.csv", encoding="utf-8"))}
    col = {"mandarina": "mandarina", "puré": "pure", "ensalada": "ensalada", "arroz": "arroz", "pollo apanado": "pollo_apanado"}
    pf = subprocess.Popen(["kubectl", "-n", "comedor", "port-forward", "deploy/ia-ml-service", f"{PUERTO}:8080"],
                          env={**os.environ, **AWS}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        esperar_api(pf)
        r = requests.post(f"{API}/ml/vision/referencia", timeout=300,
                          files={"file": ("bandeja_llena.jpg", jpeg(ImageOps.exif_transpose(Image.open(carpeta / "bandeja_llena.jpeg")).convert("RGB")), "image/jpeg")},
                          data={"plato_id": plato, "fecha": fecha, "turno": turno})
        r.raise_for_status()
        ref = r.json()
        print(f"REFERENCIA {plato} {fecha} {turno} id {ref['id']}: " + ", ".join(f"{s['nombre']} ({s['zonas']} zonas)" for s in ref["sectores"]))
        print("\nfoto              " + "".join(f"{n:>22s}" for n in col) + "      promedio")
        errores = []
        for f in sorted(carpeta.glob("bandeja_[0-9]*.jpg")):
            b = requests.post(f"{API}/ml/vision/bandeja", data={"ref_id": ref["id"]}, timeout=300,
                              files={"file": (f.name, jpeg(Image.open(f).convert("RGB")), "image/jpeg")}).json()
            got = {s["nombre"]: s["restante"] for s in b["sectores"]}
            v = {n: float(verdad[f.name][c]) for n, c in col.items()}
            errores += [abs(got.get(n, 0) - v[n]) for n in col]
            print(f"{f.name:16s}  " + "".join(f"{got.get(n, 0):10.0f} (csv {v[n]:4.0f})  " for n in col)
                  + f"   {b['restantePct']:5.1f} (csv {np.mean(list(v.values())):.1f})")
        print(f"\nerror medio por sector contra etiquetas.csv: {np.mean(errores):.1f} puntos (peor {max(errores):.0f})")
    finally:
        pf.terminate()


def main():
    if "--pollo" in sys.argv:
        return pollo()
    fechas = ultimo_servicio()
    print(f"platos con fecha de ultimo servicio: {len(fechas)}")
    if SECO:
        for p, ref, reales, nombres in pares():
            print(f"  {p:26s} ref #{ref:2d} reales {reales} ultimo {fechas.get(p)} sectores {nombres}")
        return
    if REHACER:
        borrar_demo(sorted({p for p, *_ in pares()}))

    pf = subprocess.Popen(["kubectl", "-n", "comedor", "port-forward", "deploy/ia-ml-service", f"{PUERTO}:8080"],
                          env={**os.environ, **AWS}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        esperar_api(pf)
        registradas, resumen = [], {}
        # 1) referencias + bandejas sinteticas
        for plato, i_ref, reales, nombres in pares():
            fecha, turno = fechas.get(plato, ("2026-11-09", "ALMUERZO"))
            img = abrir(i_ref)
            r = requests.post(f"{API}/ml/vision/referencia", files={"file": (f"ref_{plato}.jpg", jpeg(img), "image/jpeg")},
                              data={"plato_id": plato, "fecha": fecha, "turno": turno, "nombres": json.dumps(nombres, ensure_ascii=False)},
                              timeout=300)
            if r.status_code != 200:
                print(f"REF {plato} #{i_ref} FALLO {r.status_code}: {r.text[:160]}"); continue
            ref = r.json()
            secs = ", ".join(f"{s['nombre']}({s['zonas']})" for s in ref.get("sectores") or [])
            print(f"REF {plato} #{i_ref} {fecha} {turno} -> id {ref['id']} sectores: {secs}")
            registradas.append((plato, i_ref, reales, ref))
            for k, comido in enumerate(COMIDO_SINTETICO + (COMIDO_EXTRA if EXTRA else [])):
                sint = bandeja_sintetica(img, ref["mascara"], comido, semilla=hash((plato, i_ref, k)) % 10000)
                rb = requests.post(f"{API}/ml/vision/bandeja", files={"file": (f"sint_{plato}_{k}.jpg", jpeg(sint), "image/jpeg")},
                                   data={"ref_id": ref["id"]}, timeout=300)
                if rb.status_code == 200:
                    resumen.setdefault(plato, []).append(rb.json()["restantePct"])
                else:
                    print(f"   sintetica {comido} FALLO {rb.status_code}: {rb.text[:120]}")
        # 2) fotos reales comidas, al final: son las que aparecen primero en «Ultimas fotos analizadas»
        print("\nBANDEJAS REALES (por sector y promedio)")
        for plato, i_ref, reales, ref in registradas:
            for i in reales:
                rb = requests.post(f"{API}/ml/vision/bandeja", files={"file": (f"bandeja_{i}.jpg", jpeg(abrir(i)), "image/jpeg")},
                                   data={"ref_id": ref["id"]}, timeout=300)
                if rb.status_code != 200:
                    print(f"   #{i_ref}->#{i} FALLO {rb.status_code}: {rb.text[:120]}"); continue
                b = rb.json()
                resumen.setdefault(plato, []).append(b["restantePct"])
                print(f"  {plato:24s} #{i_ref:>2}->#{i:>2}: {texto_sectores(b)} | promedio {b['restantePct']}%")
        print("\nRESUMEN plato / bandejas / restante medio")
        for p, v in resumen.items():
            print(f"  {p:26s} {len(v):2d} {round(float(np.mean(v)), 1)}")
    finally:
        pf.terminate()


if __name__ == "__main__":
    main()
