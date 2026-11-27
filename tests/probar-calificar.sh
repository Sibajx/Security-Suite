#!/usr/bin/env bash
# Prueba de calificar.py: recall sobre el ejemplo, trampas (solo cuentan fuera de "descartados") y secretos completos.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; C="$R/tests/calificar.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
campo() { python3 -c "import json,sys; d=json.load(sys.stdin); print($1)"; }

chk "ejemplo: recall 31/31" "$(python3 "$C" "$R/docs/ejemplo-diagnostico.md" --json | campo "d['recall']")" "31/31"
chk "ejemplo: 0 trampas (están en descartados)" "$(python3 "$C" "$R/docs/ejemplo-diagnostico.md" --json | campo "len(d['trampas_reportadas'])")" 0

mkdir -p "$T/r"
printf '## Hallazgos\n#### E1 · ORDER BY dinámico en /productos — ALTA\n\n## Lo que se revisó y se descartó\n- /etag md5 — ALTA no\n' > "$T/r/DIAGNOSTICO.md"
chk "trampa en un hallazgo cuenta; en descartados no" "$(python3 "$C" "$T/r" --json | campo "','.join(d['trampas_reportadas'])")" "T1"

bash "$R/tests/crear-fixture.sh" "$T/fx" >/dev/null
clave=$(grep -o 'sk-proj-[0-9a-f]*' "$T/fx/frontend/src/config.js")
mkdir -p "$T/r2/evidencia"; echo "# x" > "$T/r2/DIAGNOSTICO.md"; echo "clave: $clave" > "$T/r2/evidencia/notas.md"
chk "ejemplo rapido-ia: 17/17 y 0 trampas" "$(python3 "$C" "$R/docs/ejemplo-rapido-ia.md" --esperado "$R/tests/esperado-next.json" --json | campo "d['recall'] + ' ' + str(len(d['trampas_reportadas']))")" "17/17 0"
chk "secreto completo en la evidencia se detecta" "$(python3 "$C" "$T/r2" --fixture "$T/fx" --json | campo "len(d['secretos_completos'])")" 1
echo "clave: ${clave:0:4}…" > "$T/r2/evidencia/notas.md"
chk "secreto redactado no cuenta" "$(python3 "$C" "$T/r2" --fixture "$T/fx" --json | campo "len(d['secretos_completos'])")" 0
python3 "$C" "$T/no-existe" >/dev/null 2>&1; chk "reporte inexistente sale 2" "$?" 2
exit $fallas
