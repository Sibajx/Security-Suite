#!/usr/bin/env python3
"""Resume los JSON de los escáneres en una tabla corta para los agentes (ahorra tokens y quita ruido).

Lee de <evidencia>/: semgrep.json, gitleaks-*.json, pip-audit-*.json y npm-audit*.json. Escribe
<evidencia>/escaneo-compacto.md: por regla/paquete, `archivo:línea` y UNA línea de código, sin duplicados.
Los agentes leen esto primero y abren el JSON original solo si necesitan más detalle.

  python3 resumir-escaneo.py <proyecto> <evidencia> [--max-por-regla 12]

Solo lee archivos locales. Los secretos salen redactados (gitleaks ya corre con --redact; además se recortan aquí).
"""
import argparse, glob, json, os, re, sys

ORDEN_SEV = {"ERROR": 0, "CRITICAL": 0, "critical": 0, "WARNING": 1, "HIGH": 1, "high": 1,
             "moderate": 2, "MEDIUM": 2, "INFO": 3, "LOW": 3, "low": 3, "info": 4}


def cargar(ruta):
    try:
        with open(ruta) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def linea_de(proyecto, ruta, n, cache={}):
    p = ruta if os.path.isabs(ruta) else os.path.join(proyecto, ruta)
    if p not in cache:
        try:
            cache[p] = open(p, errors="ignore").read().splitlines()
        except OSError:
            cache[p] = []
    lineas = cache[p]
    t = lineas[n - 1].strip() if 0 < n <= len(lineas) else ""
    t = re.sub(r"(sk-[A-Za-z0-9_\-]{4})[A-Za-z0-9_\-]{8,}", r"\1…", t)  # por si acaso
    return (t[:117] + "…") if len(t) > 120 else t


def regla_corta(check_id):
    """Las reglas locales llegan con la ruta del archivo delante; las del registro son largas."""
    if "security-suite." in check_id:
        return "security-suite." + check_id.split("security-suite.")[-1]
    partes = check_id.split(".")
    return ".".join(partes[-2:]) if len(partes) > 2 else check_id


def celda(s):
    return str(s).replace("|", "\\|").replace("`", "'")


def semgrep(proyecto, ev, maximo):
    d = cargar(os.path.join(ev, "semgrep.json"))
    if not d:
        return ["## semgrep", "", "_sin semgrep.json_"]
    grupos = {}
    for r in d.get("results", []):
        g = grupos.setdefault(regla_corta(r["check_id"]), {"sev": r["extra"].get("severity", "INFO"),
                                                          "msg": r["extra"].get("message", ""), "hits": []})
        clave = (r["path"], r["start"]["line"])
        if clave not in [h[:2] for h in g["hits"]]:
            g["hits"].append((r["path"], r["start"]["line"], linea_de(proyecto, r["path"], r["start"]["line"])))
    total = sum(len(g["hits"]) for g in grupos.values())
    L = [f"## semgrep — {total} coincidencias en {len(grupos)} reglas (pistas, no veredictos)", ""]
    for regla, g in sorted(grupos.items(), key=lambda kv: (ORDEN_SEV.get(kv[1]["sev"], 5), -len(kv[1]["hits"]))):
        msg = re.sub(r"\s+", " ", g["msg"])[:160]
        L.append(f"### `{regla}` · {g['sev']} · {len(g['hits'])}")
        L.append(f"{msg}")
        for ruta, n, codigo in g["hits"][:maximo]:
            L.append(f"- `{ruta}:{n}` — `{celda(codigo)}`")
        if len(g["hits"]) > maximo:
            L.append(f"- … y {len(g['hits']) - maximo} más (ver semgrep.json)")
        L.append("")
    if d.get("errors"):
        L.append(f"_semgrep reportó {len(d['errors'])} errores de análisis (archivos que no pudo leer)._")
    return L


def gitleaks(ev):
    L = []
    for ruta in sorted(glob.glob(os.path.join(ev, "gitleaks-*.json"))):
        d = cargar(ruta) or []
        donde = "historial" if "historial" in ruta else "árbol"
        grupos = {}
        for h in d:
            g = grupos.setdefault((h.get("RuleID"), h.get("File")), {"lineas": set(), "commits": set()})
            g["lineas"].add(h.get("StartLine"))
            if h.get("Commit"):
                g["commits"].add(h["Commit"][:7])
        L += [f"## gitleaks ({donde}) — {len(d)} hallazgos en {len(grupos)} archivo/regla", ""]
        if grupos:
            L += ["| Regla | Archivo:líneas | Commits |", "|---|---|---|"]
            for (regla, archivo), g in sorted(grupos.items(), key=lambda kv: str(kv[0])):
                lineas = ",".join(str(x) for x in sorted(x for x in g["lineas"] if x))
                commits = " ".join(sorted(g["commits"])[:5]) + (" …" if len(g["commits"]) > 5 else "")
                L.append(f"| {regla} | `{archivo}:{lineas}` | {commits or '—'} |")
        L.append("")
    return L


def version(v):
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.\-+]", v))


def pip_audit(ev):
    L = []
    for ruta in sorted(glob.glob(os.path.join(ev, "pip-audit-*.json"))):
        d = cargar(ruta) or {}
        deps = [x for x in d.get("dependencies", []) if x.get("vulns")]
        n = sum(len(x["vulns"]) for x in deps)
        L += [f"## pip-audit `{os.path.basename(ruta)}` — {n} vulnerabilidades en {len(deps)} paquetes", ""]
        if deps:
            L += ["| Paquete | Versión | Vulns | Versión mínima segura | IDs |", "|---|---|---|---|---|"]
            for x in sorted(deps, key=lambda x: -len(x["vulns"])):
                minimos = [min(v["fix_versions"], key=version) for v in x["vulns"] if v.get("fix_versions")]
                segura = max(minimos, key=version) if minimos else "sin arreglo"
                ids = ", ".join(sorted({(v.get("aliases") or [v["id"]])[0] for v in x["vulns"]})[:4])
                L.append(f"| {x['name']} | {x['version']} | {len(x['vulns'])} | {segura} | {ids}"
                         + (" …" if len(x["vulns"]) > 4 else "") + " |")
        L.append("")
    return L


def npm_audit(ev):
    L = []
    for ruta in sorted(glob.glob(os.path.join(ev, "npm-audit*.json"))):
        d = cargar(ruta) or {}
        vulns = d.get("vulnerabilities", {})
        L += [f"## npm audit `{os.path.basename(ruta)}` — {len(vulns)} paquetes afectados", ""]
        if vulns:
            L += ["| Paquete | Severidad | Directa | Qué | Arreglo |", "|---|---|---|---|---|"]
            for nombre, v in sorted(vulns.items(), key=lambda kv: ORDEN_SEV.get(kv[1].get("severity"), 5)):
                titulos = [x.get("title", "") for x in v.get("via", []) if isinstance(x, dict)]
                que = titulos[0][:70] if titulos else "vía " + ", ".join(x for x in v.get("via", []) if isinstance(x, str))[:60]
                fa = v.get("fixAvailable")
                arreglo = (f"{fa.get('name')}@{fa.get('version')}" + (" (major)" if fa.get("isSemVerMajor") else "")
                           if isinstance(fa, dict) else ("npm audit fix" if fa else "sin arreglo"))
                L.append(f"| {nombre} | {v.get('severity')} | {'sí' if v.get('isDirect') else 'no'} | {celda(que)} | {arreglo} |")
        L.append("")
    return L


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proyecto")
    ap.add_argument("evidencia")
    ap.add_argument("--max-por-regla", type=int, default=12)
    a = ap.parse_args()
    if not os.path.isdir(a.evidencia):
        print(f"No existe {a.evidencia}", file=sys.stderr); sys.exit(2)
    L = ["# Escaneo compacto (para los agentes)", "",
         "Resumen de los JSON de esta carpeta. Léelo primero; abre el JSON original solo si te falta detalle.", ""]
    L += semgrep(a.proyecto, a.evidencia, a.max_por_regla) + gitleaks(a.evidencia) + pip_audit(a.evidencia) + npm_audit(a.evidencia)
    salida = os.path.join(a.evidencia, "escaneo-compacto.md")
    open(salida, "w").write("\n".join(L) + "\n")
    print(salida)


if __name__ == "__main__":
    main()
