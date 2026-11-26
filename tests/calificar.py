#!/usr/bin/env python3
"""Califica un DIAGNOSTICO.md contra la hoja de respuestas del fixture (tests/esperado.json).

Mide lo que importa para mejorar la suite sin adivinar:
  - recall: fallas plantadas encontradas / total (y preguntas ❓ esperadas)
  - precisión: trampas reportadas como falla (cada una resta)
  - higiene: ¿algún secreto del fixture aparece COMPLETO en el reporte o su evidencia?
  - costo: tokens de las transcripciones de Claude Code (--transcript, uno o varios .jsonl)

  python3 tests/calificar.py <carpeta-del-reporte-o-DIAGNOSTICO.md> [--esperado tests/esperado.json]
      [--fixture /tmp/fixture-ss] [--transcript ~/.claude/projects/<p>/<sesion>.jsonl ...] [--json]

La coincidencia es por patrones (regex) sobre el texto: es una aproximación. Un "no encontrada" se revisa a mano
antes de concluir que la suite falló. Sale 0 siempre que pudo calificar; 2 si faltan archivos.
"""
import argparse, glob, json, os, re, subprocess, sys

DESCARTE = re.compile(r"^#{2,4} .*(descart|no son fallas|trampas)", re.I)
SEVERIDAD = re.compile(r"CR[IÍ]TICA|\bALTA\b|\bMEDIA\b|\bBAJA\b|❌")


def secciones(texto):
    """(texto sin la sección de descartados, bloques fuera de esa sección)."""
    fuera, dentro = [], False
    for linea in texto.splitlines():
        if re.match(r"^#{2,4} ", linea):
            dentro = bool(DESCARTE.match(linea))
        if not dentro:
            fuera.append(linea)
    limpio = "\n".join(fuera)
    bloques = [b for b in re.split(r"\n\s*\n|\n(?=#{2,4} )", limpio) if b.strip()]
    # una fila de tabla es su propio bloque
    filas = []
    for b in bloques:
        filas.extend(b.splitlines() if b.lstrip().startswith("|") else [b])
    return limpio, filas


def alguna(patrones, texto):
    return any(re.search(p, texto, re.I) for p in patrones)


def secretos_del_fixture(fixture):
    vals = set()
    if not fixture or not os.path.isdir(fixture):
        return vals
    try:
        primero = subprocess.run(["git", "-C", fixture, "rev-list", "--max-parents=0", "HEAD"],
                                 capture_output=True, text=True).stdout.split()[0]
        env = subprocess.run(["git", "-C", fixture, "show", f"{primero}:.env"], capture_output=True, text=True).stdout
        for linea in env.splitlines():
            v = linea.partition("=")[2].strip()
            m = re.search(r":([0-9a-f]{16,})@", v)  # contraseña dentro de DATABASE_URL
            vals.update(x for x in ([m.group(1)] if m else []) + [v] if len(x) >= 16)
    except (IndexError, OSError):
        pass
    cfg = os.path.join(fixture, "frontend/src/config.js")
    if os.path.exists(cfg):
        vals.update(re.findall(r"sk-proj-[0-9a-f]{20,}", open(cfg).read()))
    return vals


def tokens(rutas):
    vistos, total = set(), {"entrada": 0, "salida": 0, "cache_escrita": 0, "cache_leida": 0}
    for patron in rutas:
        for ruta in glob.glob(os.path.expanduser(patron)):
            for linea in open(ruta, errors="ignore"):
                try:
                    d = json.loads(linea)
                except ValueError:
                    continue
                m = d.get("message") if isinstance(d, dict) else None
                u = m.get("usage") if isinstance(m, dict) else None
                if not u:
                    continue
                clave = m.get("id") or d.get("uuid")
                if clave in vistos:  # el streaming repite el mismo mensaje
                    continue
                vistos.add(clave)
                total["entrada"] += u.get("input_tokens", 0) or 0
                total["salida"] += u.get("output_tokens", 0) or 0
                total["cache_escrita"] += u.get("cache_creation_input_tokens", 0) or 0
                total["cache_leida"] += u.get("cache_read_input_tokens", 0) or 0
    total["total"] = sum(total.values())
    return total if vistos else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("reporte")
    ap.add_argument("--esperado", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "esperado.json"))
    ap.add_argument("--fixture")
    ap.add_argument("--transcript", nargs="*", default=[])
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    diag = a.reporte if a.reporte.endswith(".md") else os.path.join(a.reporte, "DIAGNOSTICO.md")
    if not os.path.exists(diag) or not os.path.exists(a.esperado):
        print(f"No existe {diag if not os.path.exists(diag) else a.esperado}", file=sys.stderr)
        sys.exit(2)
    esperado = json.load(open(a.esperado))
    texto = open(diag, errors="ignore").read()
    limpio, bloques = secciones(texto)

    fallas = [(f["id"], f["titulo"], alguna(f["patrones"], limpio)) for f in esperado["fallas"]]
    preguntas = [(p["id"], p["titulo"], alguna(p["patrones"], texto)) for p in esperado.get("preguntas", [])]
    trampas = [(t["id"], t["titulo"], any(alguna(t["patrones"], b) and SEVERIDAD.search(b) for b in bloques))
               for t in esperado["trampas"]]

    # higiene: secretos completos en el reporte o en su evidencia
    carpeta = os.path.dirname(os.path.abspath(diag))
    fugas = []
    secretos = secretos_del_fixture(a.fixture)
    if secretos:
        for raiz, _, archivos in os.walk(carpeta):
            for nombre in archivos:
                ruta = os.path.join(raiz, nombre)
                try:
                    contenido = open(ruta, errors="ignore").read()
                except OSError:
                    continue
                fugas += [f"{os.path.relpath(ruta, carpeta)}: {s[:4]}…" for s in secretos if s in contenido]
    tok = tokens(a.transcript)

    enc = sum(1 for *_, ok in fallas if ok)
    res = {"reporte": diag, "recall": f"{enc}/{len(fallas)}", "recall_pct": round(100 * enc / len(fallas)),
           "preguntas": f"{sum(1 for *_, ok in preguntas if ok)}/{len(preguntas)}",
           "trampas_reportadas": [i for i, _, ok in trampas if ok],
           "no_encontradas": [i for i, _, ok in fallas if not ok],
           "secretos_completos": fugas if a.fixture else "sin --fixture: no revisado",
           "tokens": tok}
    if a.json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
        return
    L = [f"# Calificación — {os.path.relpath(diag)}", "",
         f"- **Recall:** {res['recall']} ({res['recall_pct']} %) · preguntas esperadas: {res['preguntas']}",
         f"- **Trampas reportadas como falla:** {len(res['trampas_reportadas'])}"
         + (f" ({', '.join(res['trampas_reportadas'])})" if res["trampas_reportadas"] else ""),
         f"- **Secretos completos en el reporte:** " + (("❌ " + "; ".join(fugas)) if fugas else
                                                       ("ninguno ✅" if a.fixture else "no revisado (falta --fixture)")),
         f"- **Tokens:** " + (f"{tok['total']:,} (entrada {tok['entrada']:,} · salida {tok['salida']:,} · caché escrita "
                              f"{tok['cache_escrita']:,} · caché leída {tok['cache_leida']:,})" if tok else
                              "sin transcripciones (--transcript)"),
         "", "| ID | Falla | ¿Encontrada? |", "|---|---|---|"]
    L += [f"| {i} | {t} | {'✅' if ok else '— revisar a mano'} |" for i, t, ok in fallas + preguntas]
    L += ["", "| ID | Trampa | ¿Reportada como falla? |", "|---|---|---|"]
    L += [f"| {i} | {t} | {'❌ sí' if ok else '✅ no'} |" for i, t, ok in trampas]
    L += ["", "Fila para `tests/esperado.md` → «Resultados registrados»:", "",
          f"`| <fecha> | <modelo> | {res['recall']} | {len(res['trampas_reportadas'])} | <confirmadas> | "
          f"{(str(round(tok['total'] / 1000)) + 'k tokens') if tok else '—'} |`"]
    print("\n".join(L))


if __name__ == "__main__":
    main()
