#!/usr/bin/env bash
# Prueba de reverificar.py con repros falsos (sin red ni app). Uso: bash tests/probar-reverificar.sh
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/skills/security-suite/scripts/reverificar.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/rep/evidencia/repro"; R="$T/rep/evidencia/repro"
rep() { printf '#!/usr/bin/env bash\n# ID: %s\n# TITULO: %s\n# SEVERIDAD: ALTA\n# NIVEL: %s\n# ESCRIBE: %s\n# REQUIERE: %s\n# BASE: %s\n%s\n' "$@" > "$R/$1.sh"; }
rep A1 arreglado 2 no "" http://127.0.0.1:1 'echo rechazado; exit 0'
rep A2 sigue 2 no "" http://127.0.0.1:1 'echo funcionó; exit 1'
rep A3 "login falló" 2 no "" http://127.0.0.1:1 'echo sin sesión; exit 2'
rep A4 "pide nivel 3" 3 si "" http://127.0.0.1:1 'exit 1'
rep A5 "falta variable" 1 no "NO_EXISTE_XYZ" http://127.0.0.1:1 'exit 1'
rep A6 "escribe remoto" 2 si "" https://ejemplo.invalid 'exit 1'
rep A7 "usa BASE" 1 no "" http://127.0.0.1:1 '[ "$BASE" = http://otra:9 ] && exit 0 || exit 1'
echo 'exit 1' > "$R/_preparar.sh"
printf '| ID | Hallazgo | Sev. |\n|---|---|---|\n| A1 | x | ALTA |\n| B9 | sin repro | MEDIA |\n' > "$T/rep/DIAGNOSTICO.md"
out="$T/v.md"
python3 "$S" "$T/rep" --nivel 2 --base http://otra:9 --salida "$out" >/dev/null; codigo=$?
# Sin --base, A6 apunta a un host remoto: segunda corrida solo para ese caso.
python3 "$S" "$T/rep" --nivel 3 --solo A6 --salida "$T/v6.md" >/dev/null
fallas=0
chk() { grep -q -- "$2" "$1" && echo "✅ $3" || { echo "❌ $3"; fallas=$((fallas+1)); }; }
chk "$out" "| A1 |.*✅ ARREGLADO" "salida 0 = arreglado"
chk "$out" "| A2 |.*❌ SIGUE" "salida 1 = sigue"
chk "$out" "| A3 |.*NO CONCLUYENTE" "salida 2 = no concluyente (nunca arreglado)"
chk "$out" "| A4 |.*requiere nivel 3" "respeta el nivel elegido"
chk "$out" "| A5 |.*faltan variables: NO_EXISTE_XYZ" "variables faltantes"
chk "$out" "| A7 |.*✅ ARREGLADO" "--base llega a los repros como \$BASE"
chk "$T/v6.md" "| A6 |.*no local" "no escribe contra un host remoto sin --escritura-remota"
chk "$out" "B9 · sin repro" "lista los hallazgos del diagnóstico sin repro"
grep -q "_preparar" "$out" && { echo "❌ corrió _preparar.sh"; fallas=$((fallas+1)); } || echo "✅ ignora archivos con _"
[ $codigo = 1 ] && echo "✅ sale 1 si algo sigue" || { echo "❌ código de salida $codigo"; fallas=$((fallas+1)); }
exit $fallas
