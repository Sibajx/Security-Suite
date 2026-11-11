#!/usr/bin/env bash
# Vigía: revisión pasiva (nivel 1) de TODOS los sitios autorizados y aviso de lo que cambió desde la última vez.
#  - por host: en-vivo.sh (HTTPS, headers, cookies, archivos expuestos)
#  - por dominio raíz: subdominios.sh (hosts nuevos, takeover) y correo-dns.sh (SPF/DMARC/CAA/DNSSEC)
# Guarda todo en <Reportes-securitysuite>/_vigia/<fecha>/ y escribe VIGIA.md con las diferencias.
# Pensado para correr solo cada semana (instalar-vigia.sh). Solo lecturas: no necesita permiso de nivel 2/3.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
AUT="${SECURITY_SUITE_AUTORIZADOS:-$HOME/.config/security-suite/autorizados.yml}"
[ -f "$AUT" ] || { echo "No existe $AUT" >&2; exit 1; }
REP=$(bash "$DIR/carpeta-reporte.sh" --base)
V="$REP/_vigia"; HOY="$V/$(date +%Y-%m-%d_%H%M)"; mkdir -p "$HOY"
ANT=$(ls -1d "$V"/20* 2>/dev/null | grep -v "$HOY" | tail -1)

hosts=$(grep -E '^\s*-\s*host:' "$AUT" | sed -E 's/.*host:\s*//; s/["'\'' ]//g' | grep -vE '^(localhost|127\.)')
raices=$(for h in $hosts; do echo "$h" | awk -F. '{print $(NF-1)"."$NF}'; done | sort -u)

for h in $hosts; do bash "$DIR/en-vivo.sh" "https://$h" > "$HOY/en-vivo_$h.md" 2>&1; sleep 2; done
for d in $raices; do
  bash "$DIR/subdominios.sh" "$d" "$HOY/subdominios_$d.md" >/dev/null 2>&1
  bash "$DIR/correo-dns.sh" "$d" > "$HOY/correo-dns_$d.md" 2>&1
done

# señales comparables: líneas de resultado sin fechas ni valores que cambian solos
senales() { grep -hE '^- (❌|⚠️|✅)|^\| [a-z0-9.-]+ \|' "$1" 2>/dev/null \
  | sed -E 's/[0-9]{4}-[0-9]{2}-[0-9]{2}[ _][0-9:]{4,5}//g; s/\| (CNAME [^|]*→ )?[0-9a-f.:]+ \|/| IP |/; s/\([0-9]+ bytes\)//' | sort -u; }

{
echo "# Vigía de seguridad — $(date '+%Y-%m-%d %H:%M')"
echo
echo "Sitios: $(echo $hosts | wc -w) · dominios: $(echo $raices | tr '\n' ' ')"
echo "Comparado con: ${ANT:+$(basename "$ANT")}${ANT:-— (primera corrida)}"
echo
cambios=0
for f in "$HOY"/*.md; do
  n=$(basename "$f"); [ "$n" = VIGIA.md ] && continue
  mal=$(grep -cE '^- ❌|❌' "$f"); mal=${mal:-0}
  if [ -n "$ANT" ] && [ -f "$ANT/$n" ]; then
    nuevas=$(comm -13 <(senales "$ANT/$n") <(senales "$f")); idas=$(comm -23 <(senales "$ANT/$n") <(senales "$f"))
    if [ -n "$nuevas$idas" ]; then
      cambios=$((cambios+1)); echo "## ${n%.md}"
      [ -n "$nuevas" ] && echo "$nuevas" | sed 's/^/+ /'
      [ -n "$idas" ] && echo "$idas" | sed 's/^/− (ya no) /'
      echo
    fi
  fi
  [ "$mal" -gt 0 ] && echo "- ${n%.md}: $mal señal(es) ❌ (ver $(basename "$HOY")/$n)"
done
echo
[ -n "$ANT" ] && { [ $cambios = 0 ] && echo "✅ Sin cambios desde la corrida anterior." || echo "⚠️ $cambios archivo(s) con cambios: revisa arriba (+ nuevo, − desapareció)."; }
echo
echo "_Un host nuevo en subdominios = algo que se publicó: ¿debía ser público? Agrégalo a autorizados.yml para auditarlo._"
} > "$HOY/VIGIA.md"
cp "$HOY/VIGIA.md" "$REP/VIGIA.md"
if [ -n "$ANT" ] && grep -q '⚠️ .* con cambios' "$HOY/VIGIA.md" && command -v notify-send >/dev/null; then
  notify-send -u critical "Security Suite · Vigía" "Hay cambios de seguridad en tus sitios. Ver $REP/VIGIA.md" 2>/dev/null || true
fi
echo "$REP/VIGIA.md"
