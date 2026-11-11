#!/usr/bin/env python3
"""Matriz de permisos: prueba cada ruta con cada rol (y sin sesión) y marca accesos indebidos.

Encuentra IDOR/BOLA, rutas de admin abiertas a clientes y rutas sin auth (chequeos 4, 5 y 6).
Solo stdlib. Los secretos NUNCA van en el archivo: se escriben como $VARIABLE y se leen del entorno.

  python3 matriz-permisos.py matriz.json [--salida evidencia/matriz.md] [--nivel 2] [--rps 5]
  python3 matriz-permisos.py --plantilla http://127.0.0.1:8000/openapi.json > matriz.json

Formato de matriz.json:
{
  "base": "https://app.midominio.com",
  "headers_comunes": {"CF-Access-Client-Id": "$CF_ACCESS_CLIENT_ID",
                      "CF-Access-Client-Secret": "$CF_ACCESS_CLIENT_SECRET"},
  "roles": {
    "anonimo": {},
    "ana":   {"headers": {"Authorization": "Bearer $TOKEN_ANA"}},
    "admin": {"headers": {"Cookie": "sesion=$SESION_ADMIN"}}
  },
  "pruebas": [
    {"metodo": "GET", "ruta": "/api/pedidos/1", "permitidos": ["ana", "admin"], "nota": "pedido de ana"},
    {"metodo": "POST", "ruta": "/api/cosa", "cuerpo": {"x": 1}, "permitidos": ["admin"], "escritura_ok": true}
  ]
}

Reglas: solo GET/HEAD/OPTIONS salvo que la prueba tenga "escritura_ok": true **y** --nivel 3
(y entonces solo con cuentas pentest-*). Un rol NO permitido que recibe 2xx = ❌ acceso indebido.
"""
import argparse, json, os, re, sys, time, urllib.error, urllib.request

UA = "security-suite/1.0 (auditoria autorizada)"
SEGUROS = {"GET", "HEAD", "OPTIONS"}


def expandir(v):
    def rep(m):
        n = m.group(1)
        if n not in os.environ:
            sys.exit(f"Falta la variable de entorno {n} (los secretos se pasan por entorno, no en el archivo)")
        return os.environ[n]
    return re.sub(r"\$([A-Z_][A-Z0-9_]*)", rep, v) if isinstance(v, str) else v


class _SinRedireccion(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None  # un 302/303 al login es "rechazado", no "entró": no se sigue


_ABRIR = urllib.request.build_opener(_SinRedireccion)


def pedir(url, metodo, headers, cuerpo):
    datos = None
    if cuerpo is not None:
        datos = json.dumps(cuerpo).encode()
        headers = {**headers, "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=datos, method=metodo, headers={"User-Agent": UA, **headers})
    try:
        with _ABRIR.open(req, timeout=15) as r:
            return r.status, r.read(4000)
    except urllib.error.HTTPError as e:
        return e.code, e.read(4000)
    except Exception as e:  # red, TLS…
        return 0, str(e).encode()


def plantilla(url_openapi):
    with urllib.request.urlopen(urllib.request.Request(url_openapi, headers={"User-Agent": UA}), timeout=15) as r:
        spec = json.load(r)
    base = url_openapi.rsplit("/openapi", 1)[0]
    pruebas = []
    for ruta, ops in spec.get("paths", {}).items():
        for metodo in ops:
            m = metodo.upper()
            if m not in {"GET", "POST", "PUT", "PATCH", "DELETE"}:
                continue
            p = {"metodo": m, "ruta": re.sub(r"\{[^}]+\}", "1", ruta), "permitidos": ["?"]}
            if m not in SEGUROS:
                p["escritura_ok"] = False
            pruebas.append(p)
    print(json.dumps({"base": base, "headers_comunes": {},
                      "roles": {"anonimo": {}, "usuario_a": {"headers": {"Authorization": "Bearer $TOKEN_A"}},
                                "usuario_b": {"headers": {"Authorization": "Bearer $TOKEN_B"}},
                                "admin": {"headers": {"Authorization": "Bearer $TOKEN_ADMIN"}}},
                      "pruebas": pruebas}, indent=2, ensure_ascii=False))
    print("\n// Rellena 'permitidos' de cada ruta (quién DEBERÍA entrar) y borra este comentario.", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("matriz", nargs="?")
    ap.add_argument("--plantilla", metavar="URL_OPENAPI")
    ap.add_argument("--salida")
    ap.add_argument("--nivel", type=int, default=2)
    ap.add_argument("--rps", type=float, default=5)
    a = ap.parse_args()
    if a.plantilla:
        return plantilla(a.plantilla)
    if not a.matriz:
        ap.error("falta matriz.json")
    cfg = json.load(open(a.matriz))
    base = cfg["base"].rstrip("/")
    comunes = {k: expandir(v) for k, v in cfg.get("headers_comunes", {}).items()}
    roles = {n: {k: expandir(v) for k, v in (r.get("headers") or {}).items()} for n, r in cfg["roles"].items()}
    nombres = list(roles)
    pausa = 1 / max(a.rps, 0.1)

    filas, malos, raros, omitidas = [], [], [], []
    for p in cfg["pruebas"]:
        metodo = p.get("metodo", "GET").upper()
        if metodo not in SEGUROS and not (p.get("escritura_ok") and a.nivel >= 3):
            omitidas.append(f"{metodo} {p['ruta']} (escritura: requiere nivel 3 y \"escritura_ok\": true)")
            continue
        permitidos = set(p.get("permitidos", []))
        celdas, cuerpos = [], {}
        for rol in nombres:
            cod, cuerpo = pedir(base + p["ruta"], metodo, {**comunes, **roles[rol]}, p.get("cuerpo"))
            time.sleep(pausa)
            cuerpos[rol] = cuerpo
            ok = 200 <= cod < 300
            if ok and rol not in permitidos and "?" not in permitidos:
                marca = "❌"
                malos.append((p, rol, cod))
            elif not ok and rol in permitidos and cod not in (0,):
                marca = "⚠️"
                raros.append((p, rol, cod))
            else:
                marca = ""
            celdas.append(f"{cod}{(' ' + marca) if marca else ''}")
        # mismo cuerpo que un rol permitido = el dato ajeno realmente se filtró
        for p_, rol, cod in malos:
            if p_ is p and any(cuerpos[rol] == cuerpos[r] for r in permitidos if r in cuerpos and r != rol):
                p_.setdefault("_filtra", set()).add(rol)
        filas.append(f"| `{metodo} {p['ruta']}` | {', '.join(sorted(permitidos)) or '—'} | " + " | ".join(celdas) + " |")

    out = [f"# Matriz de permisos — {base} — {time.strftime('%Y-%m-%d %H:%M')}", "",
           f"{len(filas)} rutas × {len(nombres)} roles. ❌ = un rol que NO debería entrar recibió 2xx · "
           "⚠️ = un rol permitido fue rechazado (¿token vencido o regla mal puesta?)", "",
           "| Ruta | Debería entrar | " + " | ".join(nombres) + " |",
           "|---|---|" + "---|" * len(nombres)] + filas
    out += ["", "## Accesos indebidos"]
    if malos:
        for p, rol, cod in malos:
            filtra = rol in p.get("_filtra", set())
            out.append(f"- ❌ **{rol}** entra a `{p.get('metodo','GET')} {p['ruta']}` ({cod})"
                       + (" y recibe **exactamente lo mismo** que el dueño → dato ajeno filtrado (IDOR)" if filtra else "")
                       + (f" — {p['nota']}" if p.get("nota") else ""))
    else:
        out.append("- Ninguno ✅")
    if raros:
        out += ["", "## Rechazos inesperados (revisar)"] + [f"- ⚠️ {r} → {c} en `{p['ruta']}`" for p, r, c in raros]
    if omitidas:
        out += ["", "## No probadas"] + [f"- {o}" for o in omitidas]
    texto = "\n".join(out) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto)
        print(a.salida)
    else:
        print(texto)
    sys.exit(1 if malos else 0)


if __name__ == "__main__":
    main()
