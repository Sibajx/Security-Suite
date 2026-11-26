#!/usr/bin/env python3
"""Supabase / Firebase: ¿la base queda abierta? (chequeos 10, 1 y 6). La falla #1 de las apps hechas con IA.

Estático (siempre, sin red), sobre el proyecto:
  - tablas de `public` sin `enable row level security`            → CRÍTICA (la anon key del bundle las lee/escribe)
  - políticas `using (true)` / `with check (true)`                → lectura/escritura para cualquiera (o cualquier usuario)
  - políticas que usan `user_metadata` / `raw_user_meta_data`     → CRÍTICA (el usuario edita esos datos)
  - funciones `security definer` sin `set search_path`            → MEDIA
  - `service_role` en código del navegador o en variables públicas → CRÍTICA (salta toda RLS)
  - Firebase: `allow read, write: if true`, `".read": true`        → CRÍTICA
  - tablas usadas en el código (`.from('x')`) que no están en las migraciones → probar en vivo

En vivo (--url, nivel ≥ 2): por cada tabla pide SOLO EL CONTEO (HEAD + `Prefer: count=exact`, sin cuerpo: no baja
datos) como anónimo con la anon key y, si existe $TOKEN_A, como la cuenta A. Firebase: `/.json?shallow=true` (solo claves).

  python3 supabase-rls.py <proyecto> [--url https://xxx.supabase.co --nivel 2] [--anon-env SUPABASE_ANON_KEY]
      [--token-env TOKEN_A] [--publicas productos,categorias] [--firebase-url https://p.firebaseio.com]
      [--salida evidencia/supabase.md]

--publicas: tablas que deben ser legibles por cualquiera (catálogo): no se marcan como falla.
Salida: 0 = nada grave · 1 = falla (estática o en vivo) · 2 = no se pudo revisar nada.
"""
import argparse, glob, json, os, re, sys, time, urllib.error, urllib.request

UA = "security-suite/1.0 (auditoria autorizada)"
IGNORAR = re.compile(r"/(node_modules|\.git|\.next|dist|build|\.venv|venv|coverage)/")
FRONT = re.compile(r"(^|/)(src|app|pages|components|lib|public|frontend|client)/.*\.(jsx?|tsx?|vue|svelte|astro)$")


def archivos(proyecto, patrones):
    vistos = set()
    for p in patrones:
        for r in glob.glob(os.path.join(proyecto, "**", p), recursive=True):
            if not IGNORAR.search(r.replace(os.sep, "/") + "/") and os.path.isfile(r) and r not in vistos:
                vistos.add(r)
                yield r


def leer(r):
    try:
        return open(r, errors="ignore").read()
    except OSError:
        return ""


def nombre_tabla(t):
    t = t.strip('"').lower()
    return t.split(".", 1)[1].strip('"') if t.startswith(("public.", '"public".')) else (None if "." in t else t)


def estatico(proyecto, publicas):
    hallazgos, tablas, rls, politicas = [], {}, set(), []
    for r in archivos(proyecto, ["*.sql"]):
        sql = re.sub(r"--[^\n]*", "", leer(r))
        rel = os.path.relpath(r, proyecto)
        for m in re.finditer(r"create\s+table\s+(?:if\s+not\s+exists\s+)?([\w.\"]+)", sql, re.I):
            t = nombre_tabla(m.group(1))
            if t:
                tablas.setdefault(t, f"{rel}:{sql[:m.start()].count(chr(10)) + 1}")
        for m in re.finditer(r"alter\s+table\s+(?:only\s+)?(?:if\s+exists\s+)?([\w.\"]+)\s+enable\s+row\s+level\s+security", sql, re.I):
            t = nombre_tabla(m.group(1))
            if t:
                rls.add(t)
        for m in re.finditer(r"create\s+policy\s+(\"[^\"]+\"|\w+)\s+on\s+([\w.\"]+)(.*?);", sql, re.I | re.S):
            t, cuerpo = nombre_tabla(m.group(2)), m.group(3)
            if not t:
                continue
            cmd = (re.search(r"\bfor\s+(all|select|insert|update|delete)\b", cuerpo, re.I) or [None, "all"])[1].lower()
            rol = (re.search(r"\bto\s+([\w, ]+?)(?:\s+using|\s+with|$)", cuerpo, re.I) or [None, "public"])[1].lower()
            politicas.append({"tabla": t, "nombre": m.group(1).strip('"'), "cmd": cmd, "rol": rol, "cuerpo": cuerpo,
                              "donde": f"{rel}:{sql[:m.start()].count(chr(10)) + 1}"})
        for m in re.finditer(r"create\s+(?:or\s+replace\s+)?function\s+([\w.\"]+)(.*?)(?:\$\$|\$\w+\$)", sql, re.I | re.S):
            cab = m.group(2)
            if re.search(r"security\s+definer", cab, re.I) and not re.search(r"set\s+search_path", cab, re.I):
                hallazgos.append(("MEDIA", "10", f"`{m.group(1)}` es `security definer` sin `set search_path` (y salta la RLS si se expone por RPC)",
                                  f"{rel}:{sql[:m.start()].count(chr(10)) + 1}"))

    for t, donde in sorted(tablas.items()):
        if t not in rls:
            sev = "MEDIA" if t in publicas else "CRÍTICA"
            hallazgos.append((sev, "10", f"tabla `{t}` sin `enable row level security`: con la anon key del bundle se lee y escribe completa", donde))
    for p in politicas:
        cuerpo = re.sub(r"\s+", " ", p["cuerpo"])
        abierta_lee = re.search(r"using\s*\(\s*true\s*\)", cuerpo, re.I)
        abierta_escribe = re.search(r"with\s+check\s*\(\s*true\s*\)", cuerpo, re.I) or (abierta_lee and p["cmd"] in ("all", "update", "delete"))
        quien = "cualquier usuario con sesión" if "authenticated" in p["rol"] else "cualquiera (anónimo)"
        if re.search(r"user_metadata|raw_user_meta_data", cuerpo, re.I):
            hallazgos.append(("CRÍTICA", "6", f"política «{p['nombre']}» en `{p['tabla']}` decide con `user_metadata`, que el propio usuario puede editar (`supabase.auth.updateUser`): usar `app_metadata` o una tabla de roles", p["donde"]))
        if abierta_escribe and p["cmd"] != "select":
            hallazgos.append(("CRÍTICA" if "authenticated" not in p["rol"] else "ALTA", "10",
                              f"política «{p['nombre']}» ({p['cmd']}) en `{p['tabla']}`: {quien} puede " + ("leer y escribir" if abierta_lee else "escribir") + " cualquier fila", p["donde"]))
        elif abierta_lee and p["tabla"] not in publicas:
            hallazgos.append(("ALTA", "10", f"política «{p['nombre']}» ({p['cmd']}) en `{p['tabla']}` con `using (true)`: {quien} lee todas las filas (¿es pública a propósito? → --publicas)", p["donde"]))

    usadas = set()
    for r in archivos(proyecto, ["*.js", "*.jsx", "*.ts", "*.tsx", "*.vue", "*.svelte", "*.astro", "*.py"]):
        c, rel = leer(r), os.path.relpath(r, proyecto).replace(os.sep, "/")
        usadas.update(m.lower() for m in re.findall(r"(?<!storage)\.from\(\s*['\"`](\w+)['\"`]\s*\)", c))
        cliente = "'use client'" in c or '"use client"' in c or FRONT.search(rel) and "/api/" not in rel and "server" not in rel
        publica = False
        for m in re.finditer(r"(NEXT_PUBLIC|VITE|PUBLIC|EXPO_PUBLIC|REACT_APP)_\w*SERVICE_ROLE\w*", c):
            publica = True
            hallazgos.append(("CRÍTICA", "1", f"variable pública `{m.group(0)}`: la service_role llega al navegador y salta toda la RLS", f"{rel}:{c[:m.start()].count(chr(10)) + 1}"))
        if cliente and not publica and re.search(r"service_role|SERVICE_ROLE", c):
            n = c[:re.search(r"service_role|SERVICE_ROLE", c).start()].count("\n") + 1
            hallazgos.append(("CRÍTICA", "1", "la service_role se usa en código que corre en el navegador", f"{rel}:{n}"))
    for r in archivos(proyecto, [".env", ".env.*", "*.env"]):
        c, rel = leer(r), os.path.relpath(r, proyecto)
        for m in re.finditer(r"^(NEXT_PUBLIC|VITE|PUBLIC|EXPO_PUBLIC|REACT_APP)_\w*SERVICE_ROLE\w*", c, re.M):
            hallazgos.append(("CRÍTICA", "1", f"`{m.group(0)}` en `{rel}`: una variable pública con la service_role termina en el bundle", f"{rel}:{c[:m.start()].count(chr(10)) + 1}"))

    for r in archivos(proyecto, ["firestore.rules", "storage.rules", "database.rules.json"]):
        c, rel = leer(r), os.path.relpath(r, proyecto)
        for m in re.finditer(r"allow\s+[\w, ]+:\s*if\s+true\s*;|\"\.(read|write)\"\s*:\s*true", c):
            hallazgos.append(("CRÍTICA", "10", f"regla abierta a cualquiera: `{m.group(0)}`", f"{rel}:{c[:m.start()].count(chr(10)) + 1}"))
        for m in re.finditer(r"allow\s+[\w, ]+:\s*if\s+request\.auth\s*!=\s*null\s*;", c):
            hallazgos.append(("ALTA", "6", f"`{m.group(0)}`: cualquier usuario con sesión lee/escribe los datos de todos (falta comparar con `request.auth.uid`)", f"{rel}:{c[:m.start()].count(chr(10)) + 1}"))

    fuera = sorted(usadas - set(tablas)) if tablas else []
    return hallazgos, sorted(set(tablas) | usadas), fuera, bool(tablas or usadas)


def conteo(url, tabla, apikey, bearer):
    req = urllib.request.Request(f"{url.rstrip('/')}/rest/v1/{tabla}?select=*", method="HEAD", headers={
        "User-Agent": UA, "apikey": apikey, "Authorization": f"Bearer {bearer}", "Prefer": "count=exact"})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            rango = r.headers.get("content-range", "")
            return r.status, int(rango.split("/")[-1]) if rango.split("/")[-1].isdigit() else None
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return 0, None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proyecto")
    ap.add_argument("--url")
    ap.add_argument("--anon-env", default="SUPABASE_ANON_KEY")
    ap.add_argument("--token-env", default="TOKEN_A")
    ap.add_argument("--tablas", help="tablas extra a probar en vivo, separadas por comas")
    ap.add_argument("--publicas", default="", help="tablas legibles por cualquiera a propósito")
    ap.add_argument("--firebase-url")
    ap.add_argument("--nivel", type=int, default=1)
    ap.add_argument("--salida")
    a = ap.parse_args()
    publicas = {t.strip().lower() for t in a.publicas.split(",") if t.strip()}
    hallazgos, tablas, fuera, hubo_algo = estatico(a.proyecto, publicas)
    tablas = sorted(set(tablas) | {t.strip().lower() for t in (a.tablas or "").split(",") if t.strip()})

    vivo, vivo_falla, vivo_probado = [], False, False
    if (a.url or a.firebase_url) and a.nivel < 2:
        print("Las pruebas en vivo piden el conteo de filas: requieren --nivel 2 o más.", file=sys.stderr); sys.exit(2)
    if a.url:
        anon = os.environ.get(a.anon_env)
        if not anon:
            print(f"Falta la variable {a.anon_env} (la anon key pública del bundle).", file=sys.stderr); sys.exit(2)
        token = os.environ.get(a.token_env)
        for i, t in enumerate(tablas):
            if i:
                time.sleep(0.25)
            c_anon, n_anon = conteo(a.url, t, anon, anon)
            c_a, n_a = conteo(a.url, t, anon, token) if token else (None, None)
            vivo_probado |= c_anon != 0
            if c_anon == 404:
                estado = "— no existe o no está expuesta"
            elif n_anon and t not in publicas:
                estado, vivo_falla = f"❌ un anónimo ve **{n_anon}** filas", True
            elif n_anon:
                estado = f"✅ pública a propósito ({n_anon} filas)"
            elif c_anon in (401, 403) or n_anon == 0:
                estado = "✅ un anónimo ve 0 filas" + (" (o la tabla está vacía)" if n_anon == 0 else "")
            else:
                estado = f"⚠️ respuesta {c_anon or 'sin conexión'}"
            extra = f"{n_a if n_a is not None else c_a}" if token else "—"
            vivo.append(f"| `{t}` | {c_anon or '—'} | {n_anon if n_anon is not None else '—'} | {extra} | {estado} |")
    if a.firebase_url:
        try:
            req = urllib.request.Request(a.firebase_url.rstrip("/") + "/.json?shallow=true", headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=20) as r:
                d = json.loads(r.read(200000) or b"null")
            vivo_probado = True
            if d not in (None, {}):
                vivo_falla = True
                vivo.append(f"| Firebase `/` | 200 | {len(d) if isinstance(d, dict) else '?'} claves | — | ❌ la Realtime Database responde sin sesión |")
            else:
                vivo.append("| Firebase `/` | 200 | 0 | — | ✅ vacía o sin datos visibles |")
        except urllib.error.HTTPError as e:
            vivo_probado = True
            vivo.append(f"| Firebase `/` | {e.code} | — | — | ✅ pide permiso |")
        except Exception as e:
            vivo.append(f"| Firebase `/` | — | — | — | ⚠️ {type(e).__name__} |")

    graves = [h for h in hallazgos if h[0] in ("CRÍTICA", "ALTA")]
    L = [f"# Supabase / Firebase — {os.path.abspath(a.proyecto)} — {time.strftime('%Y-%m-%d %H:%M')}", "",
         f"- Tablas conocidas: {', '.join(tablas) or 'ninguna'}" + (f" · públicas a propósito: {', '.join(sorted(publicas))}" if publicas else ""), ""]
    if fuera:
        L += [f"- ❓ Usadas en el código pero **no** creadas en las migraciones (¿creadas desde el panel?): {', '.join(fuera)} → pruébalas en vivo.", ""]
    L += ["## Estático", ""]
    if hallazgos:
        L += ["| Severidad | Chequeo | Problema | Dónde |", "|---|---|---|---|"]
        orden = {"CRÍTICA": 0, "ALTA": 1, "MEDIA": 2}
        L += [f"| {s} | {c} | {t} | `{d}` |" for s, c, t, d in sorted(hallazgos, key=lambda h: orden.get(h[0], 3))]
    else:
        L.append("Sin problemas en migraciones, reglas ni código." if hubo_algo else "No se encontraron migraciones SQL, reglas de Firebase ni uso de Supabase.")
    if vivo:
        L += ["", "## En vivo (solo conteos, sin descargar filas)", "",
              "| Tabla | Código anónimo | Filas que ve un anónimo | Filas que ve la cuenta A | Resultado |", "|---|---|---|---|---|", *vivo]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    if graves or vivo_falla:
        sys.exit(1)
    sys.exit(0 if hubo_algo or vivo_probado else 2)


if __name__ == "__main__":
    main()
