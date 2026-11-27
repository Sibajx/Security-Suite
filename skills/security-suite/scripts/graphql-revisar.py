#!/usr/bin/env python3
"""GraphQL: introspección abierta, sin límite de profundidad y errores verbosos (chequeo X13).

Estático (siempre, sin red): busca el servidor GraphQL y revisa su configuración.
  - Apollo/yoga con `introspection: true` o sin apagarla en producción          → ALTA
  - sin límite de profundidad/costo (graphql-depth-limit, graphql-armor, cost…)  → ALTA (DoS)
  - playground/GraphiQL activo                                                   → MEDIA
  - resolvers que buscan por id sin filtrar por el usuario                       → pista para revisar a mano

En vivo (--url, nivel ≥ 2), sin extraer datos:
  - manda una introspección mínima; si devuelve el esquema → introspección abierta
  - manda una consulta anidada benigna (profundidad configurable, por defecto 12) sobre `__schema`; si no la rechaza,
    probablemente no hay límite de profundidad
  - mira si los errores traen stack trace o rutas internas

  python3 graphql-revisar.py <proyecto> [--url https://app/graphql --nivel 2] [--header 'Authorization: Bearer $T']
      [--profundidad 12] [--salida evidencia/graphql.md]

Salida: 0 = nada grave · 1 = falla · 2 = no se pudo revisar (sin GraphQL en el código y sin --url).
"""
import argparse, glob, json, os, re, sys, urllib.error, urllib.request

UA = "security-suite/1.0 (auditoria autorizada)"
IGNORAR = re.compile(r"/(node_modules|\.git|\.next|dist|build|\.venv|venv|__pycache__)/")
PISTAS = re.compile(r"(?i)(apollo-?server|@apollo/server|graphql-yoga|graphql-http|express-graphql|type-graphql|"
                    r"@nestjs/graphql|postgraphile|graphene|strawberry|ariadne|graphql\.(schema|execute))")
DEPTH = re.compile(r"(?i)(depthLimit|depth-limit|graphql-armor|maxDepth|costAnalysis|cost-analysis|queryComplexity|"
                   r"createComplexity|validationRules|max_depth|QueryDepthLimiter)")


def archivos(proyecto):
    for ext in ("*.js", "*.jsx", "*.ts", "*.tsx", "*.py", "*.graphql", "*.gql"):
        for r in glob.glob(os.path.join(proyecto, "**", ext), recursive=True):
            if not IGNORAR.search(r.replace(os.sep, "/") + "/") and os.path.isfile(r):
                yield r


def leer(r):
    try:
        return open(r, errors="ignore").read()
    except OSError:
        return ""


def estatico(proyecto):
    hallazgos, usa_graphql, hay_depth = [], False, False
    for r in archivos(proyecto):
        c = leer(r); rel = os.path.relpath(r, proyecto)
        if not PISTAS.search(c):
            if DEPTH.search(c):
                hay_depth = True
            continue
        usa_graphql = True
        for m in re.finditer(r"(?i)introspection\s*[:=]\s*true", c):
            hallazgos.append(("ALTA", f"introspección activada explícitamente: cualquiera descarga el esquema", f"{rel}:{c[:m.start()].count(chr(10))+1}"))
        for m in re.finditer(r"(?i)(playground\s*[:=]\s*true|graphiql\s*[:=]\s*true|GraphiQL)", c):
            hallazgos.append(("MEDIA", "playground/GraphiQL activo: apágalo en producción", f"{rel}:{c[:m.start()].count(chr(10))+1}"))
        if DEPTH.search(c):
            hay_depth = True
    if usa_graphql and not hay_depth:
        hallazgos.append(("ALTA", "no se ve límite de profundidad/costo (graphql-depth-limit, graphql-armor, costAnalysis): "
                          "una consulta anidada puede tumbar el servidor (DoS)", "—"))
    return hallazgos, usa_graphql


def pedir(url, headers, query):
    datos = json.dumps({"query": query}).encode()
    req = urllib.request.Request(url, data=datos, method="POST",
                                 headers={"User-Agent": UA, "Content-Type": "application/json", **headers})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, r.read(20000).decode(errors="ignore")
    except urllib.error.HTTPError as e:
        return e.code, e.read(20000).decode(errors="ignore")
    except Exception as e:
        return 0, f"{type(e).__name__}: {e}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proyecto")
    ap.add_argument("--url")
    ap.add_argument("--header", action="append", default=[])
    ap.add_argument("--profundidad", type=int, default=12)
    ap.add_argument("--nivel", type=int, default=1)
    ap.add_argument("--salida")
    a = ap.parse_args()
    hallazgos, usa = estatico(a.proyecto)

    vivo, vivo_probado = [], False
    if a.url and a.nivel < 2:
        print("Las pruebas en vivo mandan consultas: requieren --nivel 2 o más.", file=sys.stderr); sys.exit(2)
    if a.url:
        headers = {}
        for h in a.header:
            k, _, v = h.partition(":")
            headers[k.strip()] = re.sub(r"\$([A-Z_][A-Z0-9_]*)", lambda m: os.environ.get(m.group(1), ""), v.strip())
        cod, cuerpo = pedir(a.url, headers, "{__schema{types{name}}}")
        vivo_probado = cod != 0
        if '"types"' in cuerpo or '"__schema"' in cuerpo:
            vivo.append(("ALTA", "introspección abierta en vivo: `{__schema{types{name}}}` devolvió el esquema"))
        elif cod and cod != 0:
            vivo.append(("ok", f"introspección: el servidor respondió {cod} sin el esquema"))
        # profundidad: anidar __type/ofType, benigno
        anidado = "{__schema{queryType{" + "fields{type{" * a.profundidad + "name" + "}}" * a.profundidad + "}}}"
        cod2, cuerpo2 = pedir(a.url, headers, anidado)
        if 200 <= cod2 < 300 and '"errors"' not in cuerpo2:
            vivo.append(("ALTA", f"consulta de profundidad {a.profundidad} aceptada: probablemente sin límite de profundidad (DoS)"))
        elif cod2:
            vivo.append(("ok", f"la consulta profunda fue rechazada ({cod2}) o dio error: puede haber límite"))
        if re.search(r"(?i)(traceback|at Object\.|/home/|/app/|node_modules|\.py\", line)", cuerpo + cuerpo2):
            vivo.append(("MEDIA", "los errores traen stack trace o rutas internas"))

    graves = [h for h in hallazgos if h[0] in ("ALTA", "CRÍTICA")] + [v for v in vivo if v[0] in ("ALTA", "CRÍTICA")]
    import time
    L = [f"# GraphQL — {os.path.abspath(a.proyecto)} — {time.strftime('%Y-%m-%d %H:%M')}", "",
         f"- GraphQL en el código: {'sí' if usa else 'no detectado'}" + (f" · objetivo en vivo: {a.url}" if a.url else ""), "",
         "## Estático", ""]
    if hallazgos:
        L += ["| Severidad | Problema | Dónde |", "|---|---|---|"] + [f"| {s} | {t} | `{d}` |" for s, t, d in hallazgos]
    else:
        L.append("Sin problemas de configuración GraphQL en el código." if usa else "No se detectó GraphQL en el proyecto.")
    if vivo:
        L += ["", "## En vivo (sin extraer datos)", ""] + [f"- {'❌' if s in ('ALTA','CRÍTICA') else ('⚠️' if s=='MEDIA' else '✅')} {t}" for s, t in vivo]
    L += ["", "Recuerda revisar a mano que **cada resolver con un id filtre por el usuario de la sesión** (BOLA): "
          "es la falla de GraphQL que ninguna herramienta confirma sola."]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(1 if graves else (0 if (usa or vivo_probado) else 2))


if __name__ == "__main__":
    main()
