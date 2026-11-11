#!/usr/bin/env python3
"""Graba un flujo real con el navegador (Playwright) y lo guarda como flujo.json para atacarlo con flujo.py.

Abre Chromium visible; tú haces el flujo a mano (agregar al carrito, pagar en modo prueba, confirmar…) y cierras
la ventana. Se guardan las peticiones fetch/XHR que cambian estado (POST/PUT/PATCH/DELETE) al dominio de la app.
Los headers de sesión NO se guardan: se reemplazan por $TOKEN / cookies del navegador al reproducir.

  uvx --with playwright python grabar-flujo.py https://app.midominio.com flujo.json [--sin-ventana --guion pasos.py]

--guion: archivo Python con una función `recorrer(page)` para grabar sin intervención (pruebas automáticas).
Requiere los navegadores de Playwright: `uvx --with playwright playwright install chromium` (una vez, ~150 MB).
"""
import argparse, glob, json, os, sys
from urllib.parse import urlparse

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    sys.exit("Falta Playwright. Córrelo así: uvx --with playwright python grabar-flujo.py …")

ESTADO = {"POST", "PUT", "PATCH", "DELETE"}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("url")
    ap.add_argument("salida")
    ap.add_argument("--sin-ventana", action="store_true")
    ap.add_argument("--guion")
    ap.add_argument("--header", action="append", default=[], help="'Authorization: Bearer xyz' para la grabación")
    a = ap.parse_args()
    dominio = urlparse(a.url).hostname
    pasos = []

    def al_pedir(req):
        if req.method not in ESTADO or req.resource_type not in ("fetch", "xhr"):
            return
        u = urlparse(req.url)
        if u.hostname != dominio and not (u.hostname or "").endswith("." + dominio.split(".", 1)[-1]):
            return
        p = {"nombre": f"{len(pasos)+1}-{u.path.rstrip('/').rsplit('/', 1)[-1] or 'raiz'}", "metodo": req.method,
             "ruta": u.path + (f"?{u.query}" if u.query else "")}
        cuerpo = req.post_data
        if cuerpo:
            try:
                p["cuerpo"] = json.loads(cuerpo)
            except ValueError:
                p["cuerpo_crudo"] = cuerpo[:2000]
        pasos.append(p)
        print(f"  grabado: {req.method} {p['ruta']}")

    extra = dict(h.split(":", 1) for h in a.header)
    extra = {k.strip(): v.strip() for k, v in extra.items()}
    with sync_playwright() as pw:
        try:
            nav = pw.chromium.launch(headless=a.sin_ventana)
        except Exception:
            # la versión de Playwright no coincide con el navegador descargado: usar cualquier Chromium ya instalado
            cands = sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium-*/chrome-*/chrome")), reverse=True)
            if not cands:
                sys.exit("No hay Chromium: uvx --with playwright playwright install chromium")
            nav = pw.chromium.launch(headless=a.sin_ventana, executable_path=cands[0])
        ctx = nav.new_context(extra_http_headers=extra or None, user_agent="security-suite/1.0 (auditoria autorizada) grabando")
        page = ctx.new_page()
        page.on("request", al_pedir)
        page.goto(a.url)
        if a.guion:
            ns = {}
            exec(open(a.guion).read(), ns)
            ns["recorrer"](page)
        else:
            print("Haz el flujo en la ventana y ciérrala cuando termines…")
            page.wait_for_event("close", timeout=0)
        nav.close()
    base = f"{urlparse(a.url).scheme}://{urlparse(a.url).netloc}"
    json.dump({"base": base, "headers": {"Authorization": "Bearer $TOKEN"} if extra else {},
               "pasos": pasos, "pasos_obligatorios": []}, open(a.salida, "w"), indent=2, ensure_ascii=False)
    print(f"{len(pasos)} pasos → {a.salida}. Revisa nombres y 'pasos_obligatorios' antes de correr flujo.py.")


if __name__ == "__main__":
    main()
