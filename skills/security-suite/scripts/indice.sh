#!/usr/bin/env bash
# Regenera INDICE.md con el estado de cada sitio/proyecto.
# Regla: una revisión parcial (solo un cambio) no puede esconder un veredicto peor de la última revisión completa.
# Por eso el semáforo es el PEOR veredicto entre la última corrida "completa" (línea **Modo:** con "completo") y
# todas las posteriores. Sin ninguna completa, se usa la última.
# Uso: bash indice.sh [carpeta-base]   (por defecto la misma que carpeta-reporte.sh)
set -uo pipefail
BASE="${1:-$(bash "$(dirname "$0")/carpeta-reporte.sh" --base)}"

nivel() { case "$1" in 🔴*) echo 3 ;; 🟠*) echo 2 ;; 🟢*) echo 1 ;; *) echo 0 ;; esac; }
veredicto() { grep -m1 -oE '(🔴|🟠|🟢)[^|]*' "$1" 2>/dev/null | head -1 | sed 's/\*//g' | cut -c1-60; }
es_completo() { head -8 "$1" 2>/dev/null | grep -qiE '\*\*Modo:?\*\*:? *completo|Modo: *completo'; }

{
  echo "# Reportes de Security Suite"
  echo; echo "_Actualizado: $(date '+%Y-%m-%d %H:%M')_"; echo
  echo "| Sitio / proyecto | Estado | Desde el reporte | Último reporte | Puntaje | Reportes |"
  echo "|---|---|---|---|---|---|"
  for s in "$BASE"/*_RSS; do
    [ -d "$s" ] || continue
    mapfile -t todos < <(ls -1d "$s"/*/ 2>/dev/null | sort)
    [ ${#todos[@]} -gt 0 ] || continue
    ult="${todos[-1]}"
    desde=0
    for i in "${!todos[@]}"; do es_completo "${todos[$i]}DIAGNOSTICO.md" && desde=$i; done
    peor=""; peor_dir=""; peor_n=-1
    for ((i=desde; i<${#todos[@]}; i++)); do
      f="${todos[$i]}DIAGNOSTICO.md"; [ -f "$f" ] || continue
      v=$(veredicto "$f"); n=$(nivel "$v")
      # empate: gana el más reciente
      if [ "$n" -ge "$peor_n" ]; then peor_n=$n; peor="$v"; peor_dir="${todos[$i]}"; fi
    done
    rel() { echo "$(basename "$s")/$(basename "$1")/DIAGNOSTICO.md"; }
    pun=$(grep -m1 -oE '[0-9]+/[0-9]+ chequeos' "${peor_dir:-$ult}DIAGNOSTICO.md" 2>/dev/null)
    otro="—"; [ "$ult" != "$peor_dir" ] && otro="[$(basename "$ult")]($(rel "$ult")) $(veredicto "${ult}DIAGNOSTICO.md" | cut -c1-4)"
    echo "| $(basename "$s" _RSS) | ${peor:-—} | ${peor_dir:+[$(basename "$peor_dir")]($(rel "$peor_dir"))} | $otro | ${pun:-—} | ${#todos[@]} |"
  done
  echo
  echo "_\"Estado\" = el peor veredicto desde la última revisión completa: una revisión parcial posterior no lo borra._"
  echo "_Para cerrar un 🟠/🔴, corre de nuevo la revisión completa después de arreglar._"
} > "$BASE/INDICE.md"
echo "$BASE/INDICE.md"
