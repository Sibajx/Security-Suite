#!/usr/bin/env python3
"""Ataca un flujo de varios pasos (checkout, canje, registro, recuperar contraseña, aprobar algo) — chequeo X4.

Corre el flujo normal y luego variantes que un atacante probaría:
  - saltar cada paso intermedio (¿se puede confirmar sin pagar? ¿cambiar la clave sin el código?)
  - repetir el último paso (¿dos pedidos con un solo pago? ¿un cupón dos veces?)
  - hacer el último paso sin haber empezado el flujo
Si una variante termina con éxito en el último paso → ❌ lógica de negocio rota.

  TOKEN=... python3 flujo.py flujo.json --cuenta-de-prueba [--salida evidencia/flujo.md]

flujo.json (o el que genera grabar-flujo.py):
{
  "base": "http://127.0.0.1:8000",
  "headers": {"Authorization": "Bearer $TOKEN"},
  "pasos": [
    {"nombre": "carrito",   "metodo": "POST", "ruta": "/api/checkout/carrito?producto=1"},
    {"nombre": "pagar",     "metodo": "POST", "ruta": "/api/checkout/pagar", "cuerpo": {"tarjeta": "prueba"}},
    {"nombre": "confirmar", "metodo": "POST", "ruta": "/api/checkout/confirmar"}
  ],
  "pasos_obligatorios": ["pagar"]      // opcional: solo prueba saltarse estos (por defecto, todos los intermedios)
}
Cada paso puede usar "formulario": {...} en vez de "cuerpo" (formularios HTML) y "exito_si": "texto" cuando la app
redirige igual al fallar y al acertar (el texto puede estar en el cuerpo o en el Location). Las redirecciones no se
siguen: un 303 cuenta como éxito salvo que el paso tenga "exito_si".
Las cookies se conservan entre pasos (como un navegador). ESCRIBE DATOS: nivel 3 y cuenta de prueba.
No pongas pasos que cobren de verdad: usa el modo de prueba del proveedor de pagos.
"""
import argparse, http.cookiejar, json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

UA = "security-suite/1.0 (auditoria autorizada)"


class _SinRedireccion(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None  # no seguir: un 303 de "listo" o de "al login" se cuenta tal cual


def exito(codigo):
    """2xx y 303/302 cuentan como éxito (las apps de formularios redirigen al terminar bien), salvo que
    se use --solo-2xx. 4xx/5xx = rechazo."""
    return 200 <= codigo < 300 or (codigo in (301, 302, 303, 307, 308) and not SOLO_2XX)


SOLO_2XX = False


def expandir(v):
    return re.sub(r"\$([A-Z_][A-Z0-9_]*)", lambda m: os.environ.get(m.group(1)) or sys.exit(f"Falta {m.group(1)}"), v)


def correr(cfg, pasos):
    jar = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar), _SinRedireccion)
    hdr = {"User-Agent": UA, **{k: expandir(v) for k, v in cfg.get("headers", {}).items()}}
    res = []
    for p in pasos:
        if "formulario" in p:   # {"formulario": {"codigo": "$CUPON"}} → application/x-www-form-urlencoded
            datos = urllib.parse.urlencode({k: expandir(str(v)) for k, v in p["formulario"].items()}).encode()
            h = dict(hdr, **{"Content-Type": "application/x-www-form-urlencoded"})
        else:
            datos = json.dumps(p["cuerpo"]).encode() if "cuerpo" in p else None
            h = dict(hdr, **({"Content-Type": "application/json"} if datos else {}))
        req = urllib.request.Request(cfg["base"].rstrip("/") + p["ruta"], data=datos, method=p.get("metodo", "POST"), headers=h)
        try:
            with op.open(req, timeout=20) as r:
                cuerpo = r.read(20000).decode(errors="ignore")
                res.append((p["nombre"], _marca(p, r.status, cuerpo, r.headers.get("location", ""))))
        except urllib.error.HTTPError as e:
            res.append((p["nombre"], _marca(p, e.code, e.read(20000).decode(errors="ignore"), e.headers.get("location", ""))))
        except Exception:
            res.append((p["nombre"], 0))
        time.sleep(0.3)
    return res


def _marca(p, codigo, cuerpo, location):
    """Con "exito_si" en el paso, el éxito lo decide ese texto (la app puede redirigir igual al fallar)."""
    if "exito_si" in p:
        return 200 if (p["exito_si"] in cuerpo or p["exito_si"] in location) else 400
    return codigo


def ok(c):
    return exito(c)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("flujo")
    ap.add_argument("--cuenta-de-prueba", action="store_true")
    ap.add_argument("--salida")
    a = ap.parse_args()
    if not a.cuenta_de_prueba:
        sys.exit("Esto escribe datos. Úsalo solo con una cuenta de prueba y agrega --cuenta-de-prueba.")
    cfg = json.load(open(a.flujo))
    pasos = cfg["pasos"]
    if len(pasos) < 2:
        sys.exit("Un flujo necesita al menos 2 pasos")
    final = pasos[-1]["nombre"]
    obligatorios = cfg.get("pasos_obligatorios") or [p["nombre"] for p in pasos[:-1]]

    L = [f"# Flujo — {cfg['base']} — {time.strftime('%Y-%m-%d %H:%M')}", "",
         "Pasos: " + " → ".join(f"`{p['nombre']}`" for p in pasos), "", "| Variante | Resultado por paso | Veredicto |", "|---|---|---|"]
    normal = correr(cfg, pasos)
    fmt = lambda r: " → ".join(f"{n} {c}" for n, c in r)
    if not all(ok(c) for _, c in normal):
        L.append(f"| Normal | {fmt(normal)} | ⚠️ el flujo normal no termina bien: revisa el archivo o el token |")
        texto = "\n".join(L) + "\n"
        print(texto) if not a.salida else (open(a.salida, "w").write(texto), print(a.salida))
        sys.exit(2)
    L.append(f"| Normal | {fmt(normal)} | ✅ referencia |")

    malos = []
    variantes = []
    for nombre in obligatorios:
        if nombre == final:
            continue
        variantes.append((f"Saltar `{nombre}`", [p for p in pasos if p["nombre"] != nombre]))
    variantes.append(("Solo el último paso", [pasos[-1]]))
    variantes.append(("Repetir el último paso", pasos + [pasos[-1]]))
    for titulo, ps in variantes:
        r = correr(cfg, ps)
        if titulo.startswith("Repetir"):
            roto = ok(r[-1][1]) and ok(r[-2][1])
        else:
            roto = ok(r[-1][1])
        if roto:
            malos.append(titulo)
        L.append(f"| {titulo} | {fmt(r)} | {'❌ **termina con éxito**' if roto else '✅ rechazado'} |")

    L += ["", "## Veredicto"]
    if malos:
        L.append("❌ **Lógica de negocio rota** (X4, ALTA): " + "; ".join(malos) + ".")
        L.append("Arreglo: el último paso debe comprobar en el SERVIDOR el estado de los anteriores (p. ej. `pagado=True` "
                 "guardado en la base, no en el cliente) y ser idempotente (marcar el carrito/cupón como usado en la misma transacción).")
    else:
        L.append("✅ El flujo no se deja saltar ni repetir.")
    L.append("\n_Anota o revierte lo que se creó con la cuenta de prueba._")
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(1 if malos else 0)


if __name__ == "__main__":
    main()
