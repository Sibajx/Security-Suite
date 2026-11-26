#!/usr/bin/env bash
# Escáneres automáticos (sin IA). Solo lee el proyecto; escribe resultados en <salida>.
# Los secretos se guardan redactados. Ningún código sale de la máquina (semgrep con --metrics=off;
# semgrep sí descarga sus reglas públicas y pip-audit/npm audit consultan bases de CVE con nombres+versiones).
# Uso: bash escaneo.sh <ruta-proyecto> <directorio-salida>
set -uo pipefail
P="$(cd "${1:?uso: escaneo.sh <proyecto> <salida>}" && pwd)"
OUT="${2:?falta directorio de salida}"
mkdir -p "$OUT"; OUT="$(cd "$OUT" && pwd)"
REGLAS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/semgrep/reglas-suite.yml"   # X10, X11, 11
export PATH="$HOME/.local/bin:$PATH"
R="$OUT/resumen.md"
echo "# Escaneo automático — $(basename "$P") — $(date '+%Y-%m-%d %H:%M')" > "$R"
nota() { echo "$*" | tee -a "$R"; }

cd "$P"

# 1. Secretos: historial de git + árbol actual (incluye archivos ignorados como .env y builds)
if command -v gitleaks >/dev/null; then
  if [ -d .git ]; then
    gitleaks git . --redact --no-banner -f json -r "$OUT/gitleaks-historial.json" >/dev/null 2>&1
    n=$(grep -c '"RuleID"' "$OUT/gitleaks-historial.json" 2>/dev/null); n=${n:-0}
    nota "- gitleaks historial de git: $n hallazgos → gitleaks-historial.json"
  fi
  gitleaks dir . --redact --no-banner -f json -r "$OUT/gitleaks-arbol.json" >/dev/null 2>&1
  n=$(grep -c '"RuleID"' "$OUT/gitleaks-arbol.json" 2>/dev/null); n=${n:-0}
  nota "- gitleaks árbol actual (incluye ignorados): $n hallazgos → gitleaks-arbol.json"
else nota "- gitleaks: NO INSTALADO (correr instalar-herramientas.sh)"; fi

# 1b. Archivos sensibles que estuvieron en git ALGUNA VEZ (gitleaks no ve valores sin formato conocido,
#     p. ej. DATABASE_URL o claves hex en un .env que luego se borró). Solo se listan NOMBRES de variables.
if [ -d .git ]; then
  {
    echo; echo "## Archivos sensibles en el historial de git (aunque ya no estén)"
    hits=0
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      case "$f" in *.example|*.sample|*.template|*.dist) continue ;; esac
      hits=1
      commits=$(git log --all --format=%h -- "$f" | tr '\n' ' ')
      primero=$(git log --all --diff-filter=A --format=%h -- "$f" | tail -1)
      ahora=$([ -n "$(git ls-files -- "$f")" ] && echo "sigue versionado" || echo "ya no está en HEAD pero SIGUE en el historial")
      vars=$(git show "$primero:$f" 2>/dev/null | grep -oE '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' | tr -d '= ' | tr '\n' ' ')
      echo "- **$f** ($ahora) — commits: $commits"
      [ -n "$vars" ] && echo "  - variables a ROTAR: $vars"
    done < <(git log --all --format= --name-only | sort -u | grep -E '(^|/)(\.env(\..+)?|[^/]*\.(pem|key|p12|pfx|sqlite3?|db)|credentials[^/]*\.json|service-account[^/]*\.json|id_(rsa|ed25519)[^/]*|\.npmrc|\.pypirc)$')
    [ $hits = 0 ] && echo "- ninguno"
  } >> "$R"
  nota "- historial de archivos sensibles → ver sección en resumen.md"
fi

# 2. Análisis estático
if command -v semgrep >/dev/null; then
  semgrep scan --config p/owasp-top-ten --config p/secrets --config p/python --config p/javascript \
    --config "$REGLAS" --metrics=off --quiet --json -o "$OUT/semgrep.json" . >/dev/null 2>"$OUT/semgrep.err"
  if [ -s "$OUT/semgrep.json" ]; then
    n=$(grep -o '"check_id"' "$OUT/semgrep.json" | wc -l)
    nota "- semgrep: $n hallazgos → semgrep.json (filtrar falsos positivos)"
  else
    # Sin red no bajan las reglas públicas: al menos las propias (webhooks, LLM, códigos) corren offline.
    semgrep scan --config "$REGLAS" --metrics=off --quiet --json -o "$OUT/semgrep.json" . >/dev/null 2>>"$OUT/semgrep.err"
    if [ -s "$OUT/semgrep.json" ]; then
      n=$(grep -o '"check_id"' "$OUT/semgrep.json" | wc -l)
      nota "- semgrep: reglas públicas no disponibles (¿sin red?); solo reglas de la suite: $n hallazgos → semgrep.json"
    else nota "- semgrep: falló (ver semgrep.err)"; fi
  fi
  # semgrep antepone la ruta del archivo a las reglas locales: «…semgrep.security-suite.webhook-sin-firma»
  n=$(grep -o '"check_id": *"[^"]*security-suite\.[a-z-]*"' "$OUT/semgrep.json" 2>/dev/null | wc -l)
  [ "$n" -gt 0 ] && nota "  - de ellos, $n de las reglas de la suite (webhooks sin firma, salida de LLM, códigos con random)"
else nota "- semgrep: NO INSTALADO"; fi

# 3. Dependencias Python
if command -v pip-audit >/dev/null; then
  found=0
  while IFS= read -r req; do
    found=1; nombre=$(echo "$req" | sed 's#^\./##; s#/#_#g')
    pip-audit -r "$req" --no-deps --disable-pip -f json -o "$OUT/pip-audit-$nombre.json" >/dev/null 2>"$OUT/pip-audit-$nombre.err" || true
    n=$(grep -o '"id": *"[A-Z]' "$OUT/pip-audit-$nombre.json" 2>/dev/null | wc -l)
    nota "- pip-audit $req: $n vulnerabilidades → pip-audit-$nombre.json"
  done < <(find . \( -name node_modules -o -name '.venv*' -o -name 'venv*' -o -name site-packages -o -name .git \) -prune -o -name 'requirements*.txt' -print)
  if [ $found = 0 ] && [ -f uv.lock ] && command -v uv >/dev/null; then
    uv export --no-hashes --format requirements-txt > "$OUT/requirements-uv.txt" 2>/dev/null && \
    pip-audit -r "$OUT/requirements-uv.txt" --no-deps --disable-pip -f json -o "$OUT/pip-audit-uv.json" >/dev/null 2>&1 || true
    nota "- pip-audit (uv.lock): $(grep -o '"id": *"[A-Z]' "$OUT/pip-audit-uv.json" 2>/dev/null | wc -l) vulnerabilidades"
  elif [ $found = 0 ] && [ -f pyproject.toml ]; then
    # sin lockfile: se audita lo instalado en el entorno virtual (puede no ser lo que instala el build)
    venv=$(ls -d .venv venv 2>/dev/null | head -1)
    if [ -n "$venv" ] && [ -x "$venv/bin/python" ]; then
      { "$venv/bin/python" -m pip freeze 2>/dev/null || uv pip freeze -p "$venv" 2>/dev/null; } | grep -vE '^-e |@ file:' > "$OUT/requirements-venv.txt"
      pip-audit -r "$OUT/requirements-venv.txt" --no-deps --disable-pip -f json -o "$OUT/pip-audit-venv.json" >/dev/null 2>&1 || true
      nota "- pip-audit ($venv, sin lockfile): $(grep -o '"id": *"[A-Z]' "$OUT/pip-audit-venv.json" 2>/dev/null | wc -l) vulnerabilidades — ⚠️ sin lockfile el build puede instalar otras versiones"
    else
      nota "- pip-audit: pyproject.toml sin lockfile ni entorno virtual → NO AUDITADO (genera un lock: uv pip compile pyproject.toml -o requirements.lock)"
    fi
  fi
else nota "- pip-audit: NO INSTALADO"; fi

# 4. Dependencias JS
while IFS= read -r lock; do
  d=$(dirname "$lock"); nombre=$(echo "$d" | tr '/.' '__')
  (cd "$d" && npm audit --omit=dev --json > "$OUT/npm-audit$nombre.json" 2>/dev/null) || true
  n=$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("metadata",{}).get("vulnerabilities",{}); print("{} (críticas {}, altas {}, moderadas {}, bajas {})".format(v.get("total","?"),v.get("critical",0),v.get("high",0),v.get("moderate",0),v.get("low",0)))' "$OUT/npm-audit$nombre.json" 2>/dev/null)
  nota "- npm audit $d: ${n:-?} vulnerabilidades en dependencias de producción → npm-audit$nombre.json"
done < <(command -v npm >/dev/null && find . -name node_modules -prune -o -name package-lock.json -print)

# 5. Archivos sensibles presentes / ignorados
{
  echo; echo "## Archivos sensibles en el árbol"
  find . \( -name node_modules -o -name .git -o -name '.venv*' -o -name 'venv*' -o -name site-packages \) -prune -o -type f \( -name '.env' -o -name '.env.*' -o -name '*.pem' -o -name '*.key' -o -name '*.p12' -o -name 'credentials*.json' -o -name '*.sqlite' -o -name '*.db' -o -name 'id_rsa*' \) -print | while read -r f; do
    if [ -d .git ] && git check-ignore -q "$f" 2>/dev/null; then echo "- $f (ignorado por git)"; else echo "- $f (**NO ignorado**)"; fi
  done
  [ -f Dockerfile ] && [ ! -f .dockerignore ] && echo "- Hay Dockerfile pero **no hay .dockerignore** (COPY . . mete .env y .git a la imagen)"
} >> "$R"

echo "Resultados en $OUT"; cat "$R"
