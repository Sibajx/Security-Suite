#!/usr/bin/env python3
"""Vuelve a atacar los hallazgos de un diagnóstico anterior y dice cuáles quedaron arreglados.

Cada hallazgo confirmado deja un script en <reporte>/evidencia/repro/<ID>.sh|.py (lo escribe el pentester o la suite).
Este programa los corre todos contra la versión nueva de la app y arma la tabla «antes → ahora».

  python3 reverificar.py <carpeta-del-reporte-anterior> --nivel 2 [--base http://127.0.0.1:8000] \\
      [--proyecto ~/Proyectos/app] [--solo P1,P2] [--salida $R/evidencia/reverificacion.md]

Contrato de cada script de reproducción (cabecera en comentarios, en las primeras 15 líneas):
  # ID: P2
  # TITULO: Devolver el premio mientras el mesero lo canjea
  # SEVERIDAD: ALTA
  # NIVEL: 3                      (nivel mínimo del menú de las reglas)
  # ESCRIBE: si|no                (si crea o cambia datos)
  # REQUIERE: PW_MESERO PW_DUENO  (variables de entorno; los secretos nunca van en el script)
  # BASE: http://127.0.0.1:18800  (contra qué se probó la primera vez; $BASE lo cambia)
Recibe por entorno BASE y PROYECTO. Sale con:
  0 = el ataque SE EJECUTÓ y fue rechazado (arreglado)
  1 = el ataque funcionó (la falla sigue)
  2 u otro = no se pudo probar (login falló, faltan datos, la app no responde…). Nunca 0 si no se llegó a atacar.
Los archivos que empiezan con «_» no se corren: `_preparar.sh` (opcional) levanta una instancia desechable e
imprime los `export` que necesitan los repros:  eval "$(bash repro/_preparar.sh)".
Los .py corren con $REPRO_PYTHON (o python3): sirve para usar el entorno virtual del proyecto si el script lo importa.
"""
import argparse, os, re, subprocess, sys, time
from pathlib import Path
from urllib.parse import urlsplit

CAMPOS = ("ID", "TITULO", "SEVERIDAD", "NIVEL", "ESCRIBE", "REQUIERE", "BASE")
LOCALES = {"127.0.0.1", "localhost", "::1", "0.0.0.0"}


def cabecera(ruta: Path) -> dict:
    datos = {}
    for linea in ruta.read_text(errors="ignore").splitlines()[:15]:
        m = re.match(r"\s*(?:#|//)\s*([A-ZÍ]+):\s*(.*)$", linea)
        if m and m.group(1) in CAMPOS:
            datos[m.group(1)] = m.group(2).strip()
    datos.setdefault("ID", ruta.stem)
    return datos


def ids_del_diagnostico(diag: Path) -> list[tuple[str, str, str]]:
    """(ID, título, severidad) de la tabla de hallazgos del DIAGNOSTICO.md anterior."""
    if not diag.exists():
        return []
    filas = []
    for linea in diag.read_text(errors="ignore").splitlines():
        m = re.match(r"\|\s*([A-Z]{1,2}\d{1,3})\s*\|\s*([^|]+)\|\s*(CRÍTICA|ALTA|MEDIA|BAJA)\s*\|", linea)
        if m:
            filas.append((m.group(1), m.group(2).strip(), m.group(3)))
    vistos, unicos = set(), []
    for f in filas:
        if f[0] not in vistos:
            vistos.add(f[0]); unicos.append(f)
    return unicos


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reporte", help="carpeta del diagnóstico anterior (la que tiene evidencia/repro/)")
    ap.add_argument("--nivel", type=int, required=True, help="nivel elegido en el menú para ESTA corrida")
    ap.add_argument("--base", help="URL de la app a probar ahora (por defecto, la BASE de cada script)")
    ap.add_argument("--proyecto", help="ruta del código (para los repro estáticos)")
    ap.add_argument("--solo", help="IDs separados por coma")
    ap.add_argument("--escritura-remota", action="store_true",
                    help="permite repros que escriben contra un host que no es local (solo con permiso explícito)")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--salida")
    a = ap.parse_args()

    rep = Path(a.reporte).expanduser().resolve()
    carpeta = rep / "evidencia" / "repro"
    scripts = sorted(p for p in carpeta.glob("*") if p.suffix in (".sh", ".py") and not p.name.startswith("_")) \
        if carpeta.is_dir() else []
    solo = {s.strip() for s in a.solo.split(",")} if a.solo else None
    logs = Path(a.salida).parent if a.salida else Path.cwd()
    logs.mkdir(parents=True, exist_ok=True)

    filas, cubiertos, sigue, dudas = [], set(), 0, 0
    for s in scripts:
        h = cabecera(s)
        if solo and h["ID"] not in solo:
            continue
        cubiertos.add(h["ID"])
        base = a.base or h.get("BASE", "")
        nivel = int(re.sub(r"\D", "", h.get("NIVEL", "1")) or 1)
        escribe = h.get("ESCRIBE", "no").lower().startswith("s")
        faltan = [v for v in h.get("REQUIERE", "").split() if not os.environ.get(v)]
        host = urlsplit(base).hostname or ""
        motivo = None
        if nivel > a.nivel:
            motivo = f"requiere nivel {nivel}"
        elif escribe and a.nivel < 3:
            motivo = "escribe datos: requiere nivel 3"
        elif escribe and host and host not in LOCALES and not a.escritura_remota:
            motivo = f"escribe datos en {host} (no local): usa --escritura-remota solo con permiso"
        elif faltan:
            motivo = "faltan variables: " + " ".join(faltan)
        if motivo:
            filas.append((h, "⏸️ NO PROBADO", motivo)); dudas += 1
            continue
        env = dict(os.environ, BASE=base, PROYECTO=str(Path(a.proyecto).expanduser()) if a.proyecto else "")
        cmd = ["bash", str(s)] if s.suffix == ".sh" else [os.environ.get("REPRO_PYTHON", "python3"), str(s)]
        t0 = time.time()
        try:
            r = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=a.timeout)
            codigo, salida, normal = r.returncode, (r.stdout + r.stderr), r.stdout
        except subprocess.TimeoutExpired:
            codigo, salida, normal = 124, f"(se pasó de {a.timeout} s)", ""
        (logs / f"repro-{h['ID']}.log").write_text(salida)
        # El veredicto del repro va en su última línea de stdout; los avisos de librerías van a stderr.
        lineas = [l for l in (normal or salida).strip().splitlines() if l.strip()]
        ultima = (lineas[-1] if lineas else "")[:160]
        if codigo == 0:
            estado = "✅ ARREGLADO"
        elif codigo == 1:
            estado = "❌ SIGUE"; sigue += 1
        else:
            estado = f"⚠️ NO CONCLUYENTE (salida {codigo})"; dudas += 1
        filas.append((h, estado, f"{ultima} · {time.time() - t0:.0f} s"))

    sin_repro = [f for f in ids_del_diagnostico(rep / "DIAGNOSTICO.md") if f[0] not in cubiertos
                 and (not solo or f[0] in solo)]
    L = [f"# Reverificación — {time.strftime('%Y-%m-%d %H:%M')}", "",
         f"- Diagnóstico de referencia: `{rep}`",
         f"- Contra: {a.base or 'la BASE de cada script'} · nivel {a.nivel}", "",
         "| ID | Hallazgo | Sev. | Ahora | Detalle |", "|---|---|---|---|---|"]
    for h, estado, det in filas:
        L.append(f"| {h['ID']} | {h.get('TITULO', '')} | {h.get('SEVERIDAD', '')} | {estado} | {det.replace('|', '/')} |")
    if sin_repro:
        L += ["", "## Sin script de reproducción (revisar con el auditor del área o a mano)", ""]
        L += [f"- {i} · {t} — {s}" for i, t, s in sin_repro]
    L += ["", f"**Resultado:** {sum(1 for _, e, _ in filas if e.startswith('✅'))} arreglados · {sigue} siguen · "
          f"{dudas} sin probar o no concluyentes · {len(sin_repro)} sin repro.",
          "_✅ solo dice que ESE ataque ya no funciona; no prueba que el arreglo no haya abierto otra cosa._"]
    texto = "\n".join(L) + "\n"
    if a.salida:
        Path(a.salida).write_text(texto); print(a.salida)
    else:
        print(texto)
    if not filas and not sin_repro:
        sys.exit(f"No hay scripts en {carpeta} ni hallazgos en el DIAGNOSTICO.md")
    sys.exit(1 if sigue else (2 if dudas else 0))


if __name__ == "__main__":
    main()
