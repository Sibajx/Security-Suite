#!/usr/bin/env python3
"""Revisa un JWT propio: configuración, clave débil (offline) y, si se da --url, si el servidor
acepta tokens manipulados (alg=none, cuerpo alterado con la firma vieja, firma con la clave adivinada).

  TOKEN=eyJ... python3 jwt-revisar.py --token-env TOKEN [--url https://app/api/yo] [--nivel 2]
       [--diccionario claves.txt] [--salida evidencia/jwt.md]

Nivel 1: solo análisis local del token. Nivel 2+: pruebas en vivo, solo GET a la URL dada.
El token se lee de una variable de entorno para que no quede en el historial del shell.
Chequeo 5 (auth). Solo stdlib.
"""
import argparse, base64, hashlib, hmac, json, os, sys, time, urllib.error, urllib.request

UA = "security-suite/1.0 (auditoria autorizada)"
CLAVES_COMUNES = ["secret", "secreto", "changeme", "password", "123456", "jwt", "jwtsecret", "jwt_secret",
                  "secretkey", "secret_key", "SECRET_KEY", "mysecret", "supersecret", "key", "test", "dev",
                  "development", "admin", "your-256-bit-secret", "your_jwt_secret", "default", "token",
                  "s3cr3t", "qwerty", "letmein", "cambiame", "clave", "django-insecure", "keyboard cat", ""]


def b64d(s):
    return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))


def b64e(b):
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode()


def firmar(cab, cue, clave, alg):
    fn = {"HS256": hashlib.sha256, "HS384": hashlib.sha384, "HS512": hashlib.sha512}[alg]
    return b64e(hmac.new(clave.encode(), f"{cab}.{cue}".encode(), fn).digest())


def pedir(url, token):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, r.read(3000)
    except urllib.error.HTTPError as e:
        return e.code, e.read(3000)
    except Exception as e:
        return 0, str(e).encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--token-env", default="TOKEN")
    ap.add_argument("--url")
    ap.add_argument("--nivel", type=int, default=2)
    ap.add_argument("--diccionario")
    ap.add_argument("--salida")
    a = ap.parse_args()
    tok = os.environ.get(a.token_env)
    if not tok:
        sys.exit(f"Pon el token en la variable de entorno {a.token_env}")
    try:
        cab_s, cue_s, firma_s = tok.split(".")
        cab, cue = json.loads(b64d(cab_s)), json.loads(b64d(cue_s))
    except Exception:
        sys.exit("No parece un JWT (tres partes base64url separadas por punto)")

    L = [f"# JWT — {time.strftime('%Y-%m-%d %H:%M')}", "", "## El token (sin la firma)",
         f"- Cabecera: `{json.dumps(cab)}`", f"- Campos: {', '.join(sorted(cue)) or '—'}", "", "## Configuración"]
    graves = []
    alg = cab.get("alg", "")
    if alg.lower() == "none":
        L.append("- ❌ **alg=none**: el token no lleva firma"); graves.append("alg none")
    elif alg.startswith("HS"):
        L.append(f"- ⚠️ {alg} (clave compartida): la clave debe ser aleatoria de ≥ 32 bytes; mejor RS256/EdDSA si varios servicios verifican")
    else:
        L.append(f"- ✅ {alg} (asimétrico)")
    for c in ("jku", "x5u", "jwk"):
        if c in cab:
            L.append(f"- ⚠️ La cabecera trae `{c}`: el servidor NO debe descargar claves de una URL que venga en el token")
    if "kid" in cab:
        L.append(f"- ℹ️ `kid`={cab['kid']!r}: el servidor debe buscarlo en una lista fija (no en archivos ni SQL)")
    ahora = time.time()
    if "exp" not in cue:
        L.append("- ❌ **Sin `exp`**: el token sirve para siempre; si se filtra, no hay forma de que caduque"); graves.append("sin exp")
    else:
        vida = cue["exp"] - cue.get("iat", ahora)
        L.append(("- ⚠️" if vida > 86400 else "- ✅") + f" Vida del token: {vida/3600:.1f} h" + (" (más de 24 h)" if vida > 86400 else ""))
    for c in ("iat", "iss", "aud"):
        if c not in cue:
            L.append(f"- ⚠️ Falta `{c}`" + (" (sin audiencia, un token de otra app del mismo emisor podría servir aquí)" if c == "aud" else ""))
    sensibles = [k for k in cue if any(s in k.lower() for s in ("pass", "clave", "secret", "tarjeta", "card", "curp", "rfc"))]
    if sensibles:
        L.append(f"- ❌ El token lleva datos sensibles legibles por cualquiera: {sensibles} (un JWT NO está cifrado)")
        graves.append("datos sensibles")
    for c in ("rol", "role", "roles", "is_admin", "admin", "scope", "permisos"):
        if c in cue:
            L.append(f"- ℹ️ El rol viaja en el token (`{c}`): correcto solo si la firma se verifica siempre; abajo se prueba")

    clave_rota = None
    if alg in ("HS256", "HS384", "HS512"):
        claves = list(CLAVES_COMUNES)
        if a.diccionario:
            claves += [l.rstrip("\n") for l in open(a.diccionario, errors="ignore")]
        for k in claves:
            if hmac.compare_digest(firmar(cab_s, cue_s, k, alg), firma_s):
                clave_rota = k
                break
        L += ["", "## Clave débil (offline, sin peticiones)"]
        if clave_rota is not None:
            L.append(f"- ❌ **CRÍTICA: la clave de firma es `{clave_rota[:2]}…` ({len(clave_rota)} caracteres), está en el diccionario.** "
                     "Cualquiera puede fabricar tokens de admin. Rotarla por `secrets.token_urlsafe(48)` e invalidar todos los tokens.")
            graves.append("clave débil")
        else:
            L.append(f"- ✅ No está entre {len(claves)} claves comunes")

    if a.url and a.nivel >= 2:
        L += ["", f"## En vivo contra `{a.url}` (solo GET)"]
        base_cod, base_cuerpo = pedir(a.url, tok)
        L.append(f"- Token original → {base_cod}")
        if not 200 <= base_cod < 300:
            L.append("- ⚠️ El token original no es aceptado: renueva el token antes de interpretar lo de abajo")
        cue_mal = dict(cue)
        for c in ("rol", "role"):
            if c in cue_mal:
                cue_mal[c] = "admin"
        if "sub" in cue_mal:
            cue_mal["sub"] = cue_mal["sub"] + 1 if isinstance(cue_mal["sub"], int) else str(cue_mal["sub"]) + "x"
        cue_mal_s = b64e(json.dumps(cue_mal, separators=(",", ":")).encode())
        pruebas = []
        for nombre_alg in ("none", "None", "NONE"):
            c = b64e(json.dumps({**cab, "alg": nombre_alg}, separators=(",", ":")).encode())
            pruebas.append((f"alg={nombre_alg}, sin firma, mismo cuerpo", f"{c}.{cue_s}."))
        pruebas.append(("Cuerpo alterado (rol/sub) con la firma original", f"{cab_s}.{cue_mal_s}.{firma_s}"))
        pruebas.append(("Firma borrada", f"{cab_s}.{cue_s}."))
        if clave_rota is not None:
            pruebas.append(("Token fabricado con la clave adivinada (rol admin)",
                            f"{cab_s}.{cue_mal_s}.{firmar(cab_s, cue_mal_s, clave_rota, alg)}"))
        for nombre, t in pruebas:
            cod, _ = pedir(a.url, t)
            time.sleep(0.25)
            acepta = 200 <= cod < 300
            if acepta and "fabricado" not in nombre:
                graves.append(nombre)
            L.append(f"- {'❌ **ACEPTADO**' if acepta else '✅ rechazado'} ({cod}) — {nombre}")
    elif a.url:
        L += ["", "_Pruebas en vivo omitidas: requieren nivel 2._"]

    L += ["", "## Veredicto", ("❌ " + "; ".join(graves)) if graves else "✅ Sin problemas graves"]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(1 if graves else 0)


if __name__ == "__main__":
    main()
