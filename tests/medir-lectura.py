#!/usr/bin/env python3
"""Mide el *contexto que lee cada auditor* y compara dos versiones de la skill (p. ej. v1.1 vs v1.2).

El ahorro de tokens de la v1.2 está en lo que cada agente lee ANTES de auditar, no en el modelo. Esto lo mide de
forma determinista (sin correr agentes): para cada auditor suma el tamaño de lo que su contrato y su archivo le mandan
leer, en dos refs de git, usando una carpeta de evidencia real para comparar los JSON crudos con `escaneo-compacto.md`.

  python3 tests/medir-lectura.py --evidencia <carpeta con semgrep.json, escaneo-compacto.md, ...>
      [--viejo ae4ff2b] [--nuevo HEAD]

Modelo de lectura (lo que dicen los archivos de cada versión, revisado a mano; si cambia el flujo, actualízalo aquí):
  v1.1: _contrato.md + SecurityChecks.md completo + todas las guías OWASP que lista el agente + los JSON crudos.
  v1.2: _contrato.md + solo los chequeos del agente (chequeos.py) + owasp/INDICE.md + escaneo-compacto.md.
Tokens ≈ caracteres / 4 (aproximación estándar; el valor absoluto importa menos que la diferencia).
Sale 0 si la versión --nuevo lee menos en total; 1 si no.
"""
import argparse, os, subprocess, sys

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SK = "skills/security-suite"
# Guías OWASP que cada agente mandaba leer por adelantado en v1.1 (de los "Guía:" de sus .md).
GUIAS_V11 = {
    "infra-secretos": [],  # no listaba guías fijas
    "acceso": ["authentication", "authorization", "business-logic", "api-security"],
    "entradas": ["injection", "xss", "csrf", "file-security", "ssrf", "deserialization", "misconfiguration",
                 "modern-threats", "languages/python", "languages/javascript"],
}
AGENTES = ["infra-secretos", "acceso", "entradas"]


def contenido(ref, ruta):
    r = subprocess.run(["git", "-C", RAIZ, "show", f"{ref}:{ruta}"], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else ""


def owasp_ruta(nombre):
    base = f"{SK}/owasp"
    return f"{base}/{nombre}.md" if "/" in nombre else f"{base}/references/{nombre}.md"


def chequeos_de(ref, agente):
    """Reproduce lo que `chequeos.py <agente>` imprime en esa versión (preámbulo + los chequeos del agente)."""
    import re
    texto = contenido(ref, f"{SK}/SecurityChecks.md")
    if not texto:
        return 0
    try:
        reparto = {}
        for fila in re.findall(r"^\| `([\w-]+)` \| ([^|]+) \|", texto, re.M):
            reparto[fila[0]] = re.findall(r"\bX?\d+\b", fila[1].split("herramientas")[0].split("dueño")[0])
        ids = reparto.get(agente, [])
        bloques, actual = {}, None
        for linea in texto.split("---", 1)[-1].splitlines():
            m = re.match(r"^\*\*(X?\d+)\. ", linea)
            if m:
                actual = m.group(1); bloques[actual] = [linea]
            elif linea.startswith("## "):
                actual = None
            elif actual:
                bloques[actual].append(linea)
        pre = len(texto.split("## Reparto")[0])
        return pre + sum(len("\n".join(bloques.get(i, []))) for i in ids)
    except Exception:
        return len(texto)


def tam(ref, ruta):
    return len(contenido(ref, ruta))


def medir(ref, evidencia, nuevo):
    filas, total = [], 0
    for a in AGENTES:
        contrato = tam(ref, f"{SK}/agentes/_contrato.md")
        agente = tam(ref, f"{SK}/agentes/{a}.md")
        if nuevo:
            checks = chequeos_de(ref, a)
            owasp = tam(ref, f"{SK}/owasp/INDICE.md")
            escaneo = os.path.getsize(os.path.join(evidencia, "escaneo-compacto.md")) if os.path.exists(os.path.join(evidencia, "escaneo-compacto.md")) else 0
        else:
            checks = tam(ref, f"{SK}/SecurityChecks.md")
            owasp = sum(tam(ref, owasp_ruta(g)) for g in GUIAS_V11[a])
            escaneo = sum(os.path.getsize(os.path.join(evidencia, f)) for f in os.listdir(evidencia)
                          if (f.startswith(("semgrep", "gitleaks", "pip-audit", "npm-audit")) and f.endswith(".json")))
        sub = contrato + agente + checks + owasp + escaneo
        total += sub
        filas.append((a, contrato, agente, checks, owasp, escaneo, sub))
    return filas, total


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--evidencia", required=True, help="carpeta con escaneo-compacto.md y los JSON de los escáneres")
    ap.add_argument("--viejo", default="ae4ff2b")
    ap.add_argument("--nuevo", default="HEAD")
    a = ap.parse_args()
    if not os.path.isdir(a.evidencia):
        print(f"No existe {a.evidencia}", file=sys.stderr); sys.exit(2)
    tok = lambda n: round(n / 4)
    viejo, tv = medir(a.viejo, a.evidencia, nuevo=False)
    nuevo, tn = medir(a.nuevo, a.evidencia, nuevo=True)
    if tv == 0:
        print(f"No se pudo leer la versión {a.viejo} (¿checkout sin historial? usa fetch-depth: 0).", file=sys.stderr); sys.exit(2)
    print(f"# Contexto que lee cada auditor — {a.viejo[:10]} (v1.1) vs {a.nuevo[:10]} (v1.2)\n")
    print("Tokens ≈ caracteres/4. 'checks' = SecurityChecks completo vs solo los del agente; "
          "'owasp' = guías por adelantado vs INDICE; 'escaneo' = JSON crudos vs escaneo-compacto.md.\n")
    print("| Agente | Versión | contrato | agente | checks | owasp | escaneo | total (tokens) |")
    print("|---|---|---|---|---|---|---|---|")
    for (a1, c, ag, ch, ow, es, su), (_, c2, ag2, ch2, ow2, es2, su2) in zip(viejo, nuevo):
        print(f"| {a1} | v1.1 | {tok(c)} | {tok(ag)} | {tok(ch)} | {tok(ow)} | {tok(es)} | **{tok(su)}** |")
        print(f"| {a1} | v1.2 | {tok(c2)} | {tok(ag2)} | {tok(ch2)} | {tok(ow2)} | {tok(es2)} | **{tok(su2)}** |")
    ahorro = round(100 * (tv - tn) / tv) if tv else 0
    print(f"\n**Total 3 auditores:** v1.1 ≈ {tok(tv):,} tokens · v1.2 ≈ {tok(tn):,} tokens · "
          f"**{ahorro}% menos** de contexto de lectura por corrida (sin contar el código del proyecto, igual en ambas).")
    print("\n_Mide lo que cada agente lee antes de auditar; el ahorro real por corrida depende además de cuánto código "
          "abra cada uno, que no cambia entre versiones._")
    sys.exit(0 if tn < tv else 1)


if __name__ == "__main__":
    main()
