#!/usr/bin/env bash
# Barrera de CI SIN modelo: corre solo lo determinista de la suite (secretos en git, reglas propias de semgrep,
# Supabase y GraphQL) y falla si hay algo grave. No reemplaza una auditoría completa (esa necesita los agentes),
# pero atrapa en cada push las fallas más caras de apps hechas con IA.
# Uso: bash ci-estatico.sh [<proyecto>] [--salida informe.md]
# Sale 0 si no hay hallazgos bloqueantes; 1 si los hay; el informe va a stdout, a --salida y a $GITHUB_STEP_SUMMARY.
set -uo pipefail
PROY="."; SALIDA=""
while [ $# -gt 0 ]; do case "$1" in --salida) SALIDA="$2"; shift 2;; *) PROY="$1"; shift;; esac; done
PROY="$(cd "$PROY" && pwd)"
SK="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$PATH"
bloq=0; info=(); detalle=()
nota() { info+=("$1"); }
grave() { detalle+=("$1"); bloq=$((bloq+1)); }

# 1) Secretos en el historial de git
if command -v gitleaks >/dev/null && [ -d "$PROY/.git" ]; then
  if ! gitleaks git "$PROY" --redact --no-banner >/dev/null 2>&1; then
    grave "🔴 **Secretos en git** (gitleaks): hay claves en el árbol o el historial. Rótalas (borrarlas no basta)."
  else nota "✅ gitleaks: sin secretos con formato conocido."; fi
else nota "⚠️ gitleaks no está o no hay git: revisión de secretos omitida."; fi

# 2) Reglas propias de semgrep (corren sin red)
if command -v semgrep >/dev/null; then
  J="$(mktemp)"
  semgrep scan --config "$SK/semgrep/reglas-suite.yml" --metrics=off --quiet --json -o "$J" "$PROY" >/dev/null 2>&1
  errs=$(python3 -c "import json;d=json.load(open('$J'));print(sum(1 for r in d['results'] if r['extra'].get('severity')=='ERROR'))" 2>/dev/null || echo 0)
  warns=$(python3 -c "import json;d=json.load(open('$J'));print(sum(1 for r in d['results'] if r['extra'].get('severity')=='WARNING'))" 2>/dev/null || echo 0)
  if [ "${errs:-0}" -gt 0 ]; then
    grave "🔴 **semgrep: $errs hallazgos graves** (webhook sin firma, service_role pública, precio del cliente…):"
    while IFS= read -r l; do detalle+=("    - $l"); done < <(python3 -c "
import json;d=json.load(open('$J'))
for r in d['results']:
    if r['extra'].get('severity')=='ERROR':
        print(r['check_id'].split('security-suite.')[-1], r['path'], 'L'+str(r['start']['line']))" 2>/dev/null | head -20)
  fi
  [ "${warns:-0}" -gt 0 ] && nota "🟠 semgrep: $warns avisos (IDOR por id, open redirect, códigos con random, LLM…) → revísalos."
  [ "${errs:-0}" = 0 ] && [ "${warns:-0}" = 0 ] && nota "✅ semgrep (reglas de la suite): sin hallazgos."
  rm -f "$J"
else nota "⚠️ semgrep no está: reglas propias omitidas."; fi

# 3) Supabase / Firebase
if ls "$PROY"/**/*.sql "$PROY"/supabase "$PROY"/firestore.rules >/dev/null 2>&1 || grep -rql "supabase\|firebase" "$PROY" --include=*.ts --include=*.js --include=*.tsx 2>/dev/null; then
  if python3 "$SK/scripts/supabase-rls.py" "$PROY" --salida "$(mktemp)" >/dev/null 2>&1; then
    nota "✅ Supabase/Firebase: sin tablas abiertas detectadas en el código."
  else [ $? -eq 1 ] && grave "🔴 **Supabase/Firebase**: tabla sin RLS, política abierta o service_role pública (ver supabase-rls.py)."; fi
fi

# 4) GraphQL (estático)
if grep -rql "apollo\|graphql-yoga\|@nestjs/graphql\|graphene\|strawberry\|ariadne" "$PROY" --include=*.ts --include=*.js --include=*.py 2>/dev/null; then
  python3 "$SK/scripts/graphql-revisar.py" "$PROY" >/dev/null 2>&1
  [ $? -eq 1 ] && grave "🔴 **GraphQL**: introspección abierta o sin límite de profundidad (ver graphql-revisar.py)."
fi

INFORME="$(mktemp)"
{
  echo "# security-suite — barrera estática de CI"
  echo
  if [ $bloq -gt 0 ]; then
    echo "## 🔴 $bloq hallazgo(s) bloqueante(s)"; echo
    for d in "${detalle[@]}"; do echo "- $d"; done
  else
    echo "## 🟢 Sin hallazgos bloqueantes en la revisión estática"
  fi
  echo; echo "### Detalle"
  for n in "${info[@]}"; do echo "- $n"; done
  echo
  echo "> Esto es solo la parte determinista. Para una auditoría completa (3 auditores + pentester + verificador),"
  echo "> corre la skill security-suite desde Claude Code sobre el proyecto."
} > "$INFORME"
cat "$INFORME"
[ -n "$SALIDA" ] && cp "$INFORME" "$SALIDA"
[ -n "${GITHUB_STEP_SUMMARY:-}" ] && cat "$INFORME" >> "$GITHUB_STEP_SUMMARY"
rm -f "$INFORME"
[ $bloq -eq 0 ]
