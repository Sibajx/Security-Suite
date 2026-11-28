#!/usr/bin/env python3
"""Webhook de pago falso: ¿tu endpoint de webhook acepta eventos que no firmó el proveedor? (chequeo X10)

Manda el MISMO evento dos veces: (A) sin ninguna firma y (B) con una firma inventada en el formato del proveedor.
Un webhook bien hecho rechaza las dos (400/401/403). Si acepta alguna (2xx), cualquiera puede marcarse como pagado.

  python3 webhook-falso.py --url https://app/api/webhooks/stripe --proveedor stripe \\
      --datos evidencia/evento.json --nivel 3 --cuenta-de-prueba [--salida evidencia/webhook.md]

--datos: el evento tal como lo manda el proveedor (modo de prueba), apuntando a un pedido `pentest-*` SIN PAGAR de
la cuenta de prueba. Ejemplo Stripe: {"id":"evt_pentest","type":"checkout.session.completed",
"data":{"object":{"id":"cs_test_pentest","metadata":{"pedido_id":"<id-pedido-de-prueba>"},"amount_total":100}}}

ESCRIBE DATOS (puede marcar el pedido de prueba como pagado): nivel 3, solo pedidos de prueba, nunca pagos reales.
Salida: 0 = rechazó las dos · 1 = aceptó alguna (falla) · 2 = no se pudo concluir (ruta no existe, 5xx, 422…).
"""
import argparse, base64, os, re, secrets, sys, time, urllib.error, urllib.request, uuid
from urllib.parse import urlparse

UA = "security-suite/1.0 (auditoria autorizada)"


def firma_falsa(proveedor):
    ahora = str(int(time.time()))
    h = secrets.token_hex(32)
    if proveedor == "stripe":
        return {"Stripe-Signature": f"t={ahora},v1={h}"}
    if proveedor == "mercadopago":
        return {"x-signature": f"ts={ahora},v1={h}", "x-request-id": str(uuid.uuid4())}
    if proveedor == "paypal":
        return {"PAYPAL-TRANSMISSION-ID": str(uuid.uuid4()),
                "PAYPAL-TRANSMISSION-TIME": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "PAYPAL-TRANSMISSION-SIG": base64.b64encode(secrets.token_bytes(256)).decode(),
                "PAYPAL-AUTH-ALGO": "SHA256withRSA",
                "PAYPAL-CERT-URL": "https://api.sandbox.paypal.com/v1/notifications/certs/CERT-pentest"}
    return {"X-Signature": f"sha256={h}", "X-Hub-Signature-256": f"sha256={h}", "X-Webhook-Timestamp": ahora}


def expandir(v):
    def var(m):
        if not os.environ.get(m.group(1)):
            print(f"Falta la variable {m.group(1)}", file=sys.stderr); sys.exit(2)
        return os.environ[m.group(1)]
    return re.sub(r"\$([A-Z_][A-Z0-9_]*)", var, v)


def enviar(url, cuerpo, headers):
    req = urllib.request.Request(url, data=cuerpo, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status, r.read(2000).decode(errors="ignore")
    except urllib.error.HTTPError as e:
        return e.code, e.read(2000).decode(errors="ignore")
    except Exception as e:  # app caída, DNS, TLS
        return 0, f"{type(e).__name__}: {e}"


def veredicto(codigo, cuerpo, exito_si):
    if codigo == 0:
        return "error", "no respondió"
    if exito_si:
        return ("aceptado", f"respuesta contiene «{exito_si}»") if exito_si in cuerpo else ("rechazado", f"{codigo} sin «{exito_si}»")
    if 200 <= codigo < 300:
        return "aceptado", f"{codigo}: lo procesó"
    if codigo in (400, 401, 403):
        return "rechazado", f"{codigo}: rechazado"
    if codigo in (404, 405):
        return "no-existe", f"{codigo}: la ruta no existe o no acepta POST"
    if codigo >= 500:
        return "dudoso", f"{codigo}: el servidor falló al procesarlo (¿lo intentó sin verificar la firma?)"
    return "dudoso", f"{codigo}: rechazado por otra razón (¿formato del evento?)"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True)
    ap.add_argument("--proveedor", choices=["stripe", "mercadopago", "paypal", "generico"], default="generico")
    ap.add_argument("--datos", required=True, help="archivo con el evento (JSON) tal como lo manda el proveedor")
    ap.add_argument("--header", action="append", default=[], help="headers extra ('Nombre: $VAR')")
    ap.add_argument("--exito-si", help="texto que solo aparece cuando el evento se procesó")
    ap.add_argument("--nivel", type=int, default=1)
    ap.add_argument("--cuenta-de-prueba", action="store_true")
    ap.add_argument("--salida")
    a = ap.parse_args()
    if a.nivel < 3 or not a.cuenta_de_prueba:
        print("Esto puede marcar un pedido como pagado: requiere --nivel 3 y --cuenta-de-prueba (pedido pentest-*).", file=sys.stderr)
        sys.exit(2)
    try:
        cuerpo = open(a.datos, "rb").read()
    except OSError as e:
        print(f"No se pudo leer --datos {a.datos}: {e}", file=sys.stderr); sys.exit(2)
    base = {"User-Agent": UA, "Content-Type": "application/json"}
    for h in a.header:
        k, _, v = h.partition(":")
        base[k.strip()] = expandir(v.strip())
    if urlparse(a.url).scheme == "https" and os.environ.get("CF_ACCESS_CLIENT_ID"):
        base["CF-Access-Client-Id"] = os.environ["CF_ACCESS_CLIENT_ID"]
        base["CF-Access-Client-Secret"] = os.environ.get("CF_ACCESS_CLIENT_SECRET", "")

    pruebas = [("A · sin firma", {}), (f"B · firma falsa ({a.proveedor})", firma_falsa(a.proveedor))]
    filas, estados = [], []
    for i, (nombre, extra) in enumerate(pruebas):
        if i:
            time.sleep(1)
        codigo, resp = enviar(a.url, cuerpo, {**base, **extra})
        estado, nota = veredicto(codigo, resp, a.exito_si)
        estados.append(estado)
        icono = {"aceptado": "❌", "rechazado": "✅"}.get(estado, "⚠️")
        recorte = re.sub(r"\s+", " ", resp)[:160].replace("|", "\\|")
        filas.append(f"| {nombre} | {codigo or '—'} | {icono} {nota} | `{recorte}` |")

    if "aceptado" in estados:
        final, salida = ("❌ **CRÍTICA (X10): el webhook acepta eventos que no firmó el proveedor.** Cualquiera puede "
                         "mandar este POST y marcar un pedido como pagado. Arreglo: verificar la firma con el cuerpo "
                         "crudo y el secreto del webhook antes de tocar la base (Stripe `construct_event`, Mercado Pago "
                         "HMAC de `x-signature`, PayPal `verify-webhook-signature`), o volver a consultar el pago a la "
                         "API del proveedor; guardar el ID del evento (idempotencia) y cruzar monto y pedido."), 1
    elif all(e == "rechazado" for e in estados):
        final, salida = "✅ Rechazó el evento sin firma y con firma falsa.", 0
    else:
        final, salida = ("⚠️ No se pudo concluir: revisa la ruta, el formato del evento o el log del servidor. "
                         "Un 5xx con evento sin firma suele indicar que intentó procesarlo antes de verificar."), 2

    L = [f"# Webhook de pago falso — POST {a.url} — {time.strftime('%Y-%m-%d %H:%M')}", "",
         f"- Proveedor simulado: {a.proveedor} · evento: `{os.path.basename(a.datos)}` ({len(cuerpo)} bytes)",
         "", "| Prueba | Código | Resultado | Respuesta (recortada) |", "|---|---|---|---|", *filas, "", final, "",
         "_Revisa en la base si el pedido de prueba quedó como pagado y anótalo en «Lo que creé en la app»._"]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(salida)


if __name__ == "__main__":
    main()
