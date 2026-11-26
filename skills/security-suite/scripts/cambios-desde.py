#!/usr/bin/env python3
"""Modo incremental: qué cambió desde el último reporte COMPLETO y qué agentes hay que volver a correr.

Lee el commit auditado de la línea `**Commit:**` del DIAGNOSTICO.md base, compara con el proyecto actual
(commits + cambios sin commitear + archivos nuevos) y clasifica cada archivo por área.

  python3 cambios-desde.py <proyecto> <DIAGNOSTICO.md base | carpeta del reporte> [--salida evidencia/cambios.md]

Imprime: archivos por agente, chequeos afectados y si conviene una revisión completa (base vieja, sin commit,
cambios grandes o dependencias/infra tocadas a fondo). Salida: 0 = incremental posible · 3 = conviene completo ·
2 = no se pudo (sin git o sin commit en el reporte).
"""
import argparse, os, re, subprocess, sys, time

# (regex sobre la ruta, agente, chequeos) — el primero que coincide gana; una ruta puede caer en varios
REGLAS = [
    (r"(^|/)(\.env[^/]*|.*\.(pem|key))$", "infra-secretos", "1, 2, 3"),
    (r"(^|/)(Dockerfile|docker-compose[^/]*|\.dockerignore|Caddyfile|nginx[^/]*\.conf|_headers|vercel\.json|netlify\.toml|wrangler\.toml|next\.config\.[jt]s)$", "infra-secretos", "16, 17, 19, 20"),
    (r"(^|/)\.github/workflows/", "infra-secretos", "X5"),
    (r"(^|/)(requirements[^/]*\.txt|pyproject\.toml|uv\.lock|poetry\.lock|package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock)$", "infra-secretos", "20 (dependencias)"),
    (r"(^|/)(supabase/|migrations?/|.*\.sql$|firestore\.rules|database\.rules\.json|prisma/schema\.prisma)", "acceso", "10, 6"),
    (r"(?i)(webhook|stripe|pago|payment|checkout|cupon|coupon|canje|saldo|wallet)", "acceso", "X4, X10"),
    (r"(?i)(auth|login|sesion|session|password|contrase|otp|token|jwt|middleware|admin|rol|role|permis)", "acceso", "4, 5, 6, 11"),
    (r"(?i)(chat|llm|openai|anthropic|prompt|asistente|assistant|agent|rag|embedding)", "entradas", "X11, 12"),
    (r"(?i)(upload|subir|subida|archivo|file|storage)", "entradas", "13, X3"),
    (r"(?i)(templates?/|components?/|\.html$|\.jinja2?$|\.astro$|\.vue$|\.svelte$|\.[jt]sx$)", "entradas", "8"),
    (r"(?i)(api/|routes?/|routers?/|views?\.py|endpoints?|controllers?/|main\.py|app\.py|server\.[jt]s|route\.[jt]s)", "acceso+entradas", "4–9, 14, 15, 18"),
]
CODIGO = re.compile(r"\.(py|js|jsx|ts|tsx|mjs|cjs|vue|svelte|astro|html|jinja2?|sql|rb|php|go|java|kt|cs)$")


def git(proyecto, *args):
    r = subprocess.run(["git", "-C", proyecto, *args], capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("proyecto")
    ap.add_argument("base")
    ap.add_argument("--salida")
    ap.add_argument("--max-dias", type=int, default=30)
    a = ap.parse_args()
    diag = a.base if a.base.endswith(".md") else os.path.join(a.base, "DIAGNOSTICO.md")
    if not os.path.exists(diag) or git(a.proyecto, "rev-parse", "HEAD") is None:
        print("Falta el DIAGNOSTICO.md base o el proyecto no es un repo git.", file=sys.stderr); sys.exit(2)
    texto = open(diag, errors="ignore").read()
    m = re.search(r"\*\*Commit:\*\*\s*`?([0-9a-f]{7,40})", texto)
    modo = re.search(r"\*\*Modo:\*\*\s*`?([\w-]+)", texto)
    fecha = re.search(r"\*\*Fecha:\*\*\s*(\d{4}-\d{2}-\d{2})", texto)
    if not m or git(a.proyecto, "cat-file", "-e", m.group(1) + "^{commit}") is None:
        print("El reporte base no trae `**Commit:**` (o ese commit no existe aquí): haz una revisión completa.", file=sys.stderr)
        sys.exit(2)
    base = m.group(1)
    cambiados = set((git(a.proyecto, "diff", "--name-only", f"{base}..HEAD") or "").split())
    cambiados |= set((git(a.proyecto, "diff", "--name-only", "HEAD") or "").split())
    cambiados |= set((git(a.proyecto, "ls-files", "--others", "--exclude-standard") or "").split())
    total = len((git(a.proyecto, "ls-files") or "").split()) or 1

    por_agente, chequeos, sin_area = {}, set(), []
    for f in sorted(cambiados):
        areas = [(ag, ch) for rx, ag, ch in REGLAS if re.search(rx, f)]
        if not areas:
            (sin_area if CODIGO.search(f) else []).append(f)
            continue
        for ag, ch in areas:
            for agente in ag.split("+"):
                por_agente.setdefault(agente, set()).add(f)
            chequeos.update(x.strip() for x in ch.split(","))
    for f in sin_area:  # código sin pista de área: lo miran acceso y entradas
        for agente in ("acceso", "entradas"):
            por_agente.setdefault(agente, set()).add(f)

    razones = []
    if modo and modo.group(1) != "completo":
        razones.append(f"el reporte base es `{modo.group(1)}`, no `completo`")
    if fecha:
        dias = (time.time() - time.mktime(time.strptime(fecha.group(1), "%Y-%m-%d"))) / 86400
        if dias > a.max_dias:
            razones.append(f"la base tiene {int(dias)} días (máx. {a.max_dias}): pudo haber CVE nuevas y cambió el contexto")
    if len(cambiados) >= 15 and len(cambiados) > 0.4 * total:
        razones.append(f"cambió el {round(100 * len(cambiados) / total)} % de los archivos")
    completo = bool(razones)

    L = [f"# Cambios desde el reporte base — {os.path.basename(os.path.abspath(a.proyecto))}", "",
         f"- Base: `{diag}` (commit `{base[:10]}`, {fecha.group(1) if fecha else 'sin fecha'}, modo {modo.group(1) if modo else '?'})",
         f"- Archivos cambiados o nuevos: **{len(cambiados)}** de {total}", ""]
    if completo:
        L += ["## ⚠️ Conviene una revisión completa", "", *[f"- {r}" for r in razones], ""]
    if not cambiados:
        L += ["Sin cambios desde la base: el reporte anterior sigue vigente para el código (las CVE nuevas no: corre",
              "igual `escaneo.sh`)."]
    else:
        L += ["## Agentes a relanzar (solo con estos archivos)", ""]
        for agente in ("infra-secretos", "acceso", "entradas"):
            if agente in por_agente:
                fs = sorted(por_agente[agente])
                L.append(f"- **{agente}** ({len(fs)}): " + ", ".join(f"`{x}`" for x in fs[:25]) + (" …" if len(fs) > 25 else ""))
        omitidos = [x for x in ("infra-secretos", "acceso", "entradas") if x not in por_agente]
        if omitidos:
            L.append(f"- Sin cambios en su área (se heredan sus resultados): {', '.join(omitidos)}")
        L += ["", f"Chequeos afectados: {', '.join(sorted(chequeos, key=lambda x: (x[0] == 'X', int(re.match(r'X?(\\d+)', x).group(1)) if re.match(r'X?\\d', x) else 99, x))) or '—'}.",
              "Los demás estados se **heredan** del reporte base y se marcan «heredado (fecha)» en la tabla."]
    texto = "\n".join(L) + "\n"
    if a.salida:
        open(a.salida, "w").write(texto); print(a.salida)
    else:
        print(texto)
    sys.exit(3 if completo else 0)


if __name__ == "__main__":
    main()
