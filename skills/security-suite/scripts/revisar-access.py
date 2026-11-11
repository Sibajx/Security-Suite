#!/usr/bin/env python3
"""Revisa las políticas de Cloudflare Access (chequeo X9): encuentra apps que en realidad están abiertas a cualquiera.

En Access, las reglas de **Include** se suman con «o»: basta cumplir UNA. Si Include tiene un selector que cualquiera
cumple (todos, «entró con PIN», «entró con tal proveedor», cualquier correo de gmail.com…), la lista de correos
de al lado no sirve de nada. Ejemplo típico: Include = [PIN, 3 correos] → cualquier correo entra.

  python3 revisar-access.py access.json [--salida evidencia/access.md]

access.json = {"apps": <result de GET /accounts/{id}/access/apps>,
               "grupos": <result de GET /accounts/{id}/access/groups>}   (la suite lo baja con la API o el MCP)
Sale 1 si hay una app abierta (CRÍTICA), 0 si no.
"""
import argparse, json, sys

DOMINIOS_PUBLICOS = {"gmail.com", "outlook.com", "hotmail.com", "yahoo.com", "icloud.com", "proton.me", "live.com"}


def regla_abierta(r: dict, grupos: dict) -> str | None:
    """Por qué esta regla de Include deja pasar a cualquiera; None si no."""
    if "everyone" in r:
        return "«Everyone»"
    if "login_method" in r or "auth_method" in r:
        return "un método de login (p. ej. One-time PIN): cualquier correo lo cumple"
    if "email_domain" in r and r["email_domain"].get("domain", "").lower() in DOMINIOS_PUBLICOS:
        return f"cualquier correo de {r['email_domain']['domain']}"
    if "ip" in r and r["ip"].get("ip") in ("0.0.0.0/0", "::/0"):
        return "todas las IP"
    if "group" in r:
        g = grupos.get(r["group"].get("id"))
        if g:
            for sub in g.get("include", []):
                motivo = regla_abierta(sub, grupos)
                if motivo:
                    return f"el grupo «{g.get('name')}» incluye {motivo}"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("archivo")
    ap.add_argument("--salida")
    a = ap.parse_args()
    datos = json.load(open(a.archivo))
    grupos = {g["id"]: g for g in datos.get("grupos", [])}
    L = ["# Cloudflare Access — políticas", "", "| App | Dominio | Política | Veredicto |", "|---|---|---|---|"]
    abiertas = 0
    for app in datos.get("apps", []):
        politicas = [p for p in app.get("policies", []) if p.get("decision") in ("allow", None)]
        bypass = [p for p in app.get("policies", []) if p.get("decision") == "bypass"]
        if bypass and not politicas:
            L.append(f"| {app.get('name')} | {app.get('domain', '')} | {bypass[0].get('name')} | ℹ️ pública a propósito "
                     "(bypass): confirma que debe serlo |")
            continue
        if not politicas and app.get("type") == "self_hosted":
            L.append(f"| {app.get('name')} | {app.get('domain', '')} | (ninguna) | ⚠️ sin política allow: nadie entra o falta revisar |")
        for p in politicas:
            # Un Require que todos cumplen no cierra nada; uno con correos o grupo sí acota.
            motivos = [m for r in p.get("include", []) if (m := regla_abierta(r, grupos))]
            acotada = any(not regla_abierta(r, grupos) for r in p.get("require", []))
            if motivos and not acotada:
                abiertas += 1
                L.append(f"| {app.get('name')} | {app.get('domain', '')} | {p.get('name')} | ❌ **abierta**: Include tiene "
                         f"{motivos[0]}. Pasa a Require o quítalo |")
            else:
                L.append(f"| {app.get('name')} | {app.get('domain', '')} | {p.get('name')} | ✅ |")
    L += ["", "**Veredicto:** " + (f"❌ {abiertas} política(s) dejan entrar a cualquiera (CRÍTICA, X9)." if abiertas
                                    else "✅ Ninguna política de Access queda abierta por error.")]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(1 if abiertas else 0)


if __name__ == "__main__":
    main()
