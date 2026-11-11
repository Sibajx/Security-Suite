#!/usr/bin/env python3
"""Condición de carrera: dispara N peticiones idénticas en el mismo instante y cuenta cuántas tienen éxito.

Para canjes, cupones, saldos, puntos, "un voto por persona", pagos dobles (chequeo X4).
Si la operación debería poder hacerse UNA vez y salen 2+ éxitos → ❌ condición de carrera.

  TOKEN=... python3 carrera.py --url https://app/api/canjear --metodo POST \\
      --header 'Authorization: Bearer $TOKEN' --datos '{"premio":1}' -n 10 --exitos-esperados 1 \\
      --cuenta-de-prueba [--salida evidencia/carrera.md]

ESCRIBE DATOS: es nivel 3. Solo con una cuenta de prueba (pentest-*) cuyo saldo puedas perder, en local/staging
o con permiso del dueño. --cuenta-de-prueba es obligatorio para confirmar que lo entendiste. Máximo 30.
"""
import argparse, json, os, re, sys, threading, time, urllib.error, urllib.request
from collections import Counter

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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", required=True)
    ap.add_argument("--metodo", default="POST")
    ap.add_argument("--header", action="append", default=[])
    ap.add_argument("--datos")
    ap.add_argument("-n", type=int, default=10)
    ap.add_argument("--exitos-esperados", type=int, default=1)
    ap.add_argument("--cuenta-de-prueba", action="store_true")
    ap.add_argument("--formulario", help="cuerpo como formulario: 'campo=valor&otro=$VAR'")
    ap.add_argument("--exito-si", help="texto que solo aparece en la respuesta de éxito (más preciso que el código)")
    ap.add_argument("--solo-2xx", action="store_true", help="no contar redirecciones como éxito")
    ap.add_argument("--salida")
    a = ap.parse_args()
    global SOLO_2XX
    SOLO_2XX = a.solo_2xx
    if not a.cuenta_de_prueba:
        sys.exit("Esto escribe datos. Úsalo solo con una cuenta de prueba y agrega --cuenta-de-prueba.")
    n = min(a.n, 30)
    headers = {"User-Agent": UA}
    for h in a.header:
        k, _, v = h.partition(":")
        headers[k.strip()] = expandir(v.strip())
    datos = a.datos.encode() if a.datos else None
    if datos and "Content-Type" not in headers:
        headers["Content-Type"] = "application/json"
    if a.formulario:
        datos = expandir(a.formulario).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    abrir = urllib.request.build_opener(_SinRedireccion)

    barrera = threading.Barrier(n)
    resultados = [None] * n

    def uno(i):
        req = urllib.request.Request(a.url, data=datos, method=a.metodo.upper(), headers=headers)
        barrera.wait()
        t0 = time.perf_counter()
        try:
            with abrir.open(req, timeout=30) as r:
                cuerpo = r.read(20000).decode(errors="ignore")
                resultados[i] = (r.status, cuerpo, r.headers.get("location", ""))
        except urllib.error.HTTPError as e:
            resultados[i] = (e.code, e.read(20000).decode(errors="ignore"), e.headers.get("location", ""))
        except Exception:
            resultados[i] = (0, "", "")

    hilos = [threading.Thread(target=uno, args=(i,)) for i in range(n)]
    for h in hilos: h.start()
    for h in hilos: h.join()

    codigos = Counter(c for c, _, _ in resultados)
    if a.exito_si:
        exitos = sum(1 for c, cuerpo, loc in resultados if a.exito_si in cuerpo or a.exito_si in loc)
    else:
        exitos = sum(1 for c, _, _ in resultados if exito(c))
    hay = exitos > a.exitos_esperados
    L = [f"# Condición de carrera — {a.metodo.upper()} {a.url} — {time.strftime('%Y-%m-%d %H:%M')}", "",
         f"- {n} peticiones simultáneas; éxitos esperados como máximo: {a.exitos_esperados}",
         f"- Respuestas: " + ", ".join(f"{c}×{v}" for c, v in sorted(codigos.items())),
         f"- Éxitos: **{exitos}**" + (f" (respuestas que contienen «{a.exito_si}»)" if a.exito_si else
                                         " (2xx" + ("" if a.solo_2xx else " y redirecciones") + "; si la app redirige también al fallar, usa --exito-si)"),
         "_Confírmalo en la base o en la pantalla: es la prueba definitiva._", "",
         ("❌ **Condición de carrera confirmada**: la operación se hizo " + str(exitos) +
          " veces. Arreglo: hacerlo atómico en la base (UPDATE … SET saldo = saldo - X WHERE id = ? AND saldo >= X y revisar "
          "filas afectadas; o SELECT … FOR UPDATE; o restricción UNIQUE; o clave de idempotencia).") if hay else
         "✅ No se reprodujo (solo " + str(exitos) + " éxito(s)).",
         "", "_Recuerda revertir o anotar lo que se creó con la cuenta de prueba._"]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(1 if hay else 0)


if __name__ == "__main__":
    main()
