"""Demo de vision: carga fotos de bandejas en el pipeline REAL de vision de ia-ml (TensorFlow en el servidor, fotos en S3):
  1) referencias: una foto de bandeja llena por plato  -> POST /ml/vision/referencia
  2) bandejas: fotos reales parcialmente comidas + variantes sinteticas (se tapa parte de la comida con el color
     de la bandeja segun la mascara que devuelve el modelo) -> POST /ml/vision/bandeja (el modelo calcula el % restante)
Usa port-forward al pod de ia-ml (credenciales de .env.cloud.nuevo). Fotos: carpeta FOTOS_BANDEJAS
(por defecto ../pagos-tickets-service/im: 36 fotos de WhatsApp; ver MAPA para saber cual es cada plato).
Uso (desde comedor-infra):
    python infra/datos/cargar_vision_demo.py --seco    # muestra el mapeo foto -> plato y fechas
    python infra/datos/cargar_vision_demo.py           # referencias + bandejas reales + 4 sinteticas por plato
    python infra/datos/cargar_vision_demo.py --extra   # 8 bandejas sinteticas mas por plato (distribucion realista)
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
IM = sorted(Path(os.environ.get("FOTOS_BANDEJAS", RAIZ.parent / "pagos-tickets-service" / "im")).glob("*.jpeg"))
SECO = "--seco" in sys.argv
PUERTO = 18080
API = f"http://localhost:{PUERTO}"

# plato del historial -> (indice de la foto llena = referencia, indices de fotos reales comidas)
MAPA = {
    # Almuerzo
    "plato-milanesa":           (17, [30, 22, 34]),
    "plato-asado-de-res":       (18, [25, 32]),
    "plato-silpancho":          (20, [26]),
    "plato-chicharron":         (29, [35]),
    "plato-charque":            (21, [23]),
    "plato-tallarin-con-carne": (24, []),
    "plato-pique-macho":        (5, []),
    "plato-arroz-con-pollo":    (12, []),
    "plato-fricase":            (13, []),
    "plato-majadito":           (9, []),
    "plato-locro":              (10, []),
    "plato-sopa-de-mani":       (14, []),
    # Cena
    "plato-pollo-frito":        (19, [27, 28, 31]),
    "plato-sopa-de-fideo":      (1, []),
    "plato-arroz-con-queso":    (16, [33]),
    "plato-tortilla-de-papa":   (0, []),
}
# fracciones de comida "comida" (quitada) para las bandejas sinteticas; el resto queda
COMIDO_SINTETICO = [0.20, 0.45, 0.70, 0.90]
# --extra: mas bandejas por plato con la distribucion real de un comedor (la mayoria casi termina el plato)
COMIDO_EXTRA = [0.97, 0.95, 0.93, 0.90, 0.88, 0.85, 0.80, 0.75]
EXTRA = "--extra" in sys.argv


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


def mascara_local(img: Image.Image) -> list:
    """Misma regla que usa el servidor para separar comida de bandeja (saturacion + textura, umbral de Otsu),
    calculada aqui para no volver a registrar la referencia."""
    REJ, LADO = 56, 224
    pq = img.resize((LADO, LADO))
    paso = LADO // REJ
    sat = (np.asarray(pq.convert("HSV"), dtype=np.float32)[..., 1] / 255.0).reshape(REJ, paso, REJ, paso).mean(axis=(1, 3)).ravel()
    tex = (np.asarray(pq.convert("L"), dtype=np.float32) / 255.0).reshape(REJ, paso, REJ, paso).std(axis=(1, 3)).ravel()
    norm = lambda v: v / (v.max() + 1e-8)
    v = norm(sat) + norm(tex)
    mejor, umbral = -1.0, float(np.median(v))
    for t in np.linspace(v.min(), v.max(), 64)[1:-1]:
        a, b = v[v <= t], v[v > t]
        if len(a) < 5 or len(b) < 5:
            continue
        w = len(a) * len(b) / len(v) ** 2 * (a.mean() - b.mean()) ** 2
        if w > mejor:
            mejor, umbral = w, float(t)
    m = (v > umbral).reshape(REJ, REJ).astype(np.float32)
    p = np.pad(m, 1, mode="edge")
    vecinos = sum(p[i:i + REJ, j:j + REJ] for i in range(3) for j in range(3))
    return (vecinos >= 5).astype(int).tolist()


def extra():
    """Agrega bandejas sinteticas (distribucion realista) a las referencias YA registradas de cada plato."""
    pf = subprocess.Popen(["kubectl", "-n", "comedor", "port-forward", "deploy/ia-ml-service", f"{PUERTO}:8080"],
                          env={**os.environ, **AWS}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            try:
                requests.get(f"{API}/health", timeout=3); break
            except Exception:
                time.sleep(1)
        refs = requests.get(f"{API}/ml/vision/referencias", timeout=60).json()
        ultima = {}
        for r in refs:                                   # la mas reciente por plato
            ultima.setdefault(r["plato_id"], r)
        for plato, (i_ref, _) in MAPA.items():
            r = ultima.get(plato)
            if not r:
                print(f"{plato}: sin referencia registrada, se salta"); continue
            img = abrir(i_ref)
            masc = mascara_local(img)
            res = []
            for k, comido in enumerate(COMIDO_EXTRA):
                sint = bandeja_sintetica(img, masc, comido, semilla=(hash((plato, "x", k)) % 10000))
                rb = requests.post(f"{API}/ml/vision/bandeja", files={"file": (f"extra_{plato}_{k}.jpg", jpeg(sint), "image/jpeg")},
                                   data={"ref_id": r["id"]}, timeout=300)
                res.append(rb.json()["restantePct"] if rb.status_code == 200 else f"ERR{rb.status_code}")
            print(f"{plato:26s} ref {r['id']} -> restantes {res}")
    finally:
        pf.terminate()


def main():
    if EXTRA:
        return extra()
    fechas = ultimo_servicio()
    print(f"platos con fecha de ultimo servicio: {len(fechas)}")
    if SECO:
        for p, (ref, reales) in MAPA.items():
            print(f"  {p:26s} ref #{ref:2d} reales {reales} ultimo {fechas.get(p)}")
        return

    pf = subprocess.Popen(["kubectl", "-n", "comedor", "port-forward", "deploy/ia-ml-service", f"{PUERTO}:8080"],
                          env={**os.environ, **AWS}, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            try:
                requests.get(f"{API}/health", timeout=3); break
            except Exception:
                time.sleep(1)
        resumen = []
        for plato, (i_ref, reales) in MAPA.items():
            fecha, turno = fechas.get(plato, ("2026-11-09", "ALMUERZO"))
            img = abrir(i_ref)
            r = requests.post(f"{API}/ml/vision/referencia", files={"file": (f"ref_{plato}.jpg", jpeg(img), "image/jpeg")},
                              data={"plato_id": plato, "fecha": fecha, "turno": turno}, timeout=300)
            if r.status_code != 200:
                print(f"REF {plato} #{i_ref} FALLO {r.status_code}: {r.text[:160]}"); continue
            ref = r.json()
            print(f"REF {plato} #{i_ref} {fecha} {turno} -> id {ref['id']} fComida {ref['fraccionComida']}" + (f" ADV: {ref['advertencia']}" if ref.get("advertencia") else ""))
            bandejas = []
            # fotos reales comidas
            for i in reales:
                rb = requests.post(f"{API}/ml/vision/bandeja", files={"file": (f"bandeja_{i}.jpg", jpeg(abrir(i)), "image/jpeg")},
                                   data={"ref_id": ref["id"]}, timeout=300)
                if rb.status_code == 200:
                    b = rb.json(); bandejas.append(("real", i, b["restantePct"], b["confianza"]))
                else:
                    print(f"   bandeja real #{i} FALLO {rb.status_code}: {rb.text[:120]}")
            # sinteticas
            for k, comido in enumerate(COMIDO_SINTETICO):
                sint = bandeja_sintetica(img, ref["mascara"], comido, semilla=hash((plato, k)) % 10000)
                rb = requests.post(f"{API}/ml/vision/bandeja", files={"file": (f"sint_{plato}_{k}.jpg", jpeg(sint), "image/jpeg")},
                                   data={"ref_id": ref["id"]}, timeout=300)
                if rb.status_code == 200:
                    b = rb.json(); bandejas.append((f"sint-{int(comido*100)}%", k, b["restantePct"], b["confianza"]))
                else:
                    print(f"   sintetica {comido} FALLO {rb.status_code}: {rb.text[:120]}")
            for tipo, i, rest, conf in bandejas:
                print(f"   bandeja {tipo:10s} #{i}: restante {rest}% (conf {conf})")
            resumen.append((plato, len(bandejas), round(float(np.mean([b[2] for b in bandejas])), 1) if bandejas else None))
        print("\nRESUMEN plato / bandejas / restante medio")
        for p, n, m in resumen:
            print(f"  {p:26s} {n:2d} {m}")
    finally:
        pf.terminate()


if __name__ == "__main__":
    main()
