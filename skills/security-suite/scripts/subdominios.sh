#!/usr/bin/env bash
# Descubre subdominios de un dominio PROPIO (o autorizado) y revisa cada uno:
#  - fuentes: Certificate Transparency (crt.sh, público) + lista de nombres típicos resueltos por DNS
#  - detecta comodín DNS (*.dominio) para no reportar falsos positivos
#  - por cada host vivo: código HTTP, título, Cloudflare Access, y CNAME colgante (posible subdomain takeover)
# Solo consultas DNS y un GET por host. Uso: bash subdominios.sh <dominio> [salida.md]
set -uo pipefail
DOM="${1:?uso: subdominios.sh <dominio> [salida.md]}"; DOM=$(echo "$DOM" | sed -E 's#^[a-z]+://##; s#/.*$##')
OUT="${2:-/dev/stdout}"
UA="security-suite/1.0 (auditoria autorizada)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
LISTA="$(dirname "$0")/subdominios-comunes.txt"

resuelve() { dig +short +time=2 +tries=1 "$1" A "$1" AAAA 2>/dev/null | grep -E '^[0-9a-f.:]+$' | head -1; }
cname()    { dig +short +time=2 +tries=1 "$1" CNAME 2>/dev/null | head -1 | sed 's/\.$//'; }

# 1. Certificate Transparency
curl -s --max-time 40 -A "$UA" "https://crt.sh/?q=%25.$DOM&output=json" 2>/dev/null \
  | jq -r '.[].name_value' 2>/dev/null | tr 'A-Z' 'a-z' | tr '\n' '\n' | sed 's/^\*\.//' \
  | grep -E "(^|\.)${DOM//./\\.}$" | sort -u > "$TMP/ct.txt"
if [ ! -s "$TMP/ct.txt" ]; then   # respaldo: certspotter (gratis, con límite de consultas)
  curl -s --max-time 40 -A "$UA" "https://api.certspotter.com/v1/issuances?domain=$DOM&include_subdomains=true&expand=dns_names" 2>/dev/null \
    | jq -r '.[].dns_names[]' 2>/dev/null | tr 'A-Z' 'a-z' | sed 's/^\*\.//' | grep -E "(^|\.)${DOM//./\\.}$" | sort -u > "$TMP/ct.txt"
fi
CT_OK=$([ -s "$TMP/ct.txt" ] && echo si || echo no)

# 2. Comodín DNS. Con Cloudflare las IPs rotan: se compara la RESPUESTA HTTP de un nombre inventado.
RAND="no-existe-ss-$RANDOM$RANDOM"
COMODIN_IP=$(resuelve "$RAND.$DOM")
huella() { # código + tamaño del cuerpo con el nombre del host normalizado
  curl -s -k -A "$UA" --max-time 10 -o "$TMP/h" -w "%{http_code}" "https://$1/" 2>/dev/null > "$TMP/hc"
  sed "s/$1/HOST/g" "$TMP/h" 2>/dev/null | wc -c | awk -v c="$(cat "$TMP/hc")" '{print c" "$1}'; }
COMODIN_HUELLA=""; [ -n "$COMODIN_IP" ] && COMODIN_HUELLA=$(huella "$RAND.$DOM")
es_comodin() { [ -n "$COMODIN_HUELLA" ] || return 1; local h c1 s1 c2 s2; h=$(huella "$1"); c1=${h% *}; s1=${h#* }; c2=${COMODIN_HUELLA% *}; s2=${COMODIN_HUELLA#* }
  [ "$c1" = "$c2" ] || return 1; [ "$s2" -eq 0 ] && [ "$s1" -eq 0 ] && return 0; [ "$s2" -gt 0 ] && [ $(( (s1-s2)*100/s2 )) -ge -3 ] && [ $(( (s1-s2)*100/s2 )) -le 3 ]; }

# 3. Lista de nombres típicos
: > "$TMP/brute.txt"; : > "$TMP/comodin.txt"
if [ -f "$LISTA" ]; then
  while read -r p; do
    [ -z "$p" ] && continue; h="$p.$DOM"; ip=$(resuelve "$h")
    [ -z "$ip" ] && continue
    if es_comodin "$h"; then echo "$h" >> "$TMP/comodin.txt"; else echo "$h" >> "$TMP/brute.txt"; fi
  done < "$LISTA"
fi

sort -u "$TMP/ct.txt" "$TMP/brute.txt" <(echo "$DOM") > "$TMP/todos.txt"

{
echo "# Subdominios de $DOM — $(date '+%Y-%m-%d %H:%M')"
echo
echo "- Certificate Transparency: $( [ $CT_OK = si ] && echo "$(wc -l < "$TMP/ct.txt") nombres" || echo "sin respuesta de crt.sh (reintentar más tarde)")"
echo "- Lista de nombres típicos: $(wc -l < "$TMP/brute.txt") con respuesta propia"
[ -n "$COMODIN_IP" ] && echo "- ℹ️ **Hay comodín DNS** (*.$DOM): $(wc -l < "$TMP/comodin.txt") nombres de la lista responden igual que uno inventado (huella HTTP \`$COMODIN_HUELLA\`) y no se distinguen desde afuera (o no existen, o están detrás de la misma puerta, p. ej. Access): $(head -40 "$TMP/comodin.txt" | sed "s/\.$DOM//" | tr '\n' ' ')"
echo
echo "| Host | Fuente | DNS | HTTP | Título / nota |"
echo "|---|---|---|---|---|"
while read -r h; do
  [ -z "$h" ] && continue
  src=""; grep -qx "$h" "$TMP/ct.txt" && src="CT"; grep -qx "$h" "$TMP/brute.txt" && src="${src:+$src+}lista"; [ "$h" = "$DOM" ] && src="raíz"
  ip=$(resuelve "$h"); cn=$(cname "$h")
  if [ -z "$ip" ]; then
    if [ -n "$cn" ]; then
      echo "| $h | $src | CNAME → $cn **sin resolver** | — | ❌ **CNAME colgante: posible subdomain takeover** — borrar el registro DNS |"
    else
      echo "| $h | $src | no resuelve | — | (certificado viejo; el nombre ya no existe) |"
    fi
    continue
  fi
  solo_comodin=""
  r=$(curl -s -k -A "$UA" --max-time 10 -o "$TMP/b" -w "%{http_code} %{redirect_url}" "https://$h/")
  code=${r%% *}; loc=${r#* }
  titulo=$(grep -o -i -m1 '<title>[^<]*' "$TMP/b" 2>/dev/null | sed 's/<title>//I' | cut -c1-50)
  nota="$titulo"
  case "$loc" in *cloudflareaccess.com*) nota="🔒 Cloudflare Access";; esac
  # firmas típicas de takeover (servicio sin el recurso detrás)
  if grep -qiE "There isn't a GitHub Pages site here|NoSuchBucket|No such app|herokucdn.com/error-pages/no-such-app|The specified bucket does not exist|project not found|Domain is not configured|This deployment cannot be found|Fastly error: unknown domain" "$TMP/b" 2>/dev/null; then
    nota="❌ **Firma de recurso inexistente: posible subdomain takeover**"
  fi
  [ "$code" = 000 ] && nota="no responde por HTTPS"
  echo "| $h | $src$solo_comodin | ${cn:+CNAME $cn → }$ip | $code | $nota |"
done < "$TMP/todos.txt"
echo
echo "_Los hosts nuevos que encuentres deben estar en tu archivo de autorizaciones antes de probarlos a fondo._"
} > "$OUT"
[ "$OUT" != /dev/stdout ] && echo "$OUT"
exit 0
