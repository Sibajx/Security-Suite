#!/usr/bin/env bash
# Fuzzing de una API a partir de su OpenAPI con Schemathesis: manda miles de entradas raras generadas del esquema
# y reporta errores 500, respuestas que no cumplen el esquema, endpoints que aceptan cosas inválidas, etc.
# Chequeos 7 y 19. ESCRIBE DATOS BASURA: solo local/staging (o producción con --produccion-autorizada y nivel 3).
#
# Uso: bash fuzz-api.sh <url-openapi> <carpeta-salida> [--solo-lectura] [--produccion-autorizada] [-H 'Header: $VAR']...
# Ej.: bash fuzz-api.sh http://127.0.0.1:8000/openapi.json "$R/evidencia" -H 'Authorization: Bearer $TOKEN_A'
set -uo pipefail
SPEC="${1:?uso: fuzz-api.sh <url-openapi> <carpeta-salida> [opciones]}"; OUT="${2:?falta carpeta de salida}"; shift 2
host=$(echo "$SPEC" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')
PROD=0; LECTURA=0; HDRS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --produccion-autorizada) PROD=1 ;;
    --solo-lectura) LECTURA=1 ;;
    -H) shift; v=$(echo "$1" | envsubst); HDRS+=(-H "$v") ;;
  esac; shift
done
case "$host" in localhost|127.*|0.0.0.0|::1|*.local|*.test|*staging*|*.invalid) ;;
  *) [ $PROD = 1 ] || { echo "❌ $host parece producción. El fuzzing escribe datos basura: úsalo en local/staging o agrega --produccion-autorizada (nivel 3, con respaldo)." >&2; exit 2; }
     LECTURA=1; echo "⚠️ Producción: solo GET y a 2 peticiones/s." >&2 ;;
esac
command -v uvx >/dev/null || { echo "Falta uv (https://docs.astral.sh/uv/) para correr schemathesis sin instalarlo" >&2; exit 2; }
mkdir -p "$OUT"
EXTRA=(); [ $LECTURA = 1 ] && EXTRA+=(--include-method GET)
RATE="10/s"; [ $PROD = 1 ] && RATE="2/s"
uvx schemathesis@4 run "$SPEC" --checks all -n 50 --rate-limit "$RATE" --max-response-time 5 \
  --report junit --report-junit-path "$OUT/fuzz-junit.xml" \
  "${EXTRA[@]}" "${HDRS[@]}" > "$OUT/fuzz-api.txt" 2>&1
codigo=$?
{
  echo "# Fuzzing de la API — $SPEC — $(date '+%Y-%m-%d %H:%M')"
  echo
  echo "Schemathesis 4, todas las comprobaciones, 50 ejemplos por operación, $RATE$( [ $LECTURA = 1 ] && echo ', solo GET')."
  echo
  echo '```'
  sed -n '/FAILURES\|Failures\|SUMMARY\|Summary/,$p' "$OUT/fuzz-api.txt" | sed 's/\x1b\[[0-9;]*m//g' | head -120
  echo '```'
  echo
  echo "Salida completa: \`fuzz-api.txt\`. Cada falla trae el \`curl\` para reproducirla. Un 500 = entrada que el código no valida (7) o error sin manejar (19)."
} > "$OUT/fuzz-api.md"
echo "$OUT/fuzz-api.md"
exit $codigo
