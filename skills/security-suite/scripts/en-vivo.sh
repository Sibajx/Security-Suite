#!/usr/bin/env bash
# Chequeos PASIVOS en vivo (nivel 1): HTTPS, headers, cookies y rutas sensibles expuestas.
# Solo peticiones GET/HEAD normales, como un navegador. Úsalo SOLO contra sitios propios
# o con autorización escrita (ver reglas-de-enfrentamiento.md).
# Uso: bash en-vivo.sh <url-base>
# Sitio detrás de Cloudflare Access: exporta CF_ACCESS_CLIENT_ID y CF_ACCESS_CLIENT_SECRET (service token de
# solo lectura, ver reglas-de-enfrentamiento.md) y la revisión entra a la app real en vez de la pantalla de Access.
set -uo pipefail
URL="${1:?uso: en-vivo.sh <url>}"; URL="${URL%/}"
UA="security-suite/1.0 (auditoria autorizada)"
HOST=$(echo "$URL" | sed -E 's#^https?://([^/]+).*#\1#')
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CFH=()
if [ -n "${CF_ACCESS_CLIENT_ID:-}" ] && [ -n "${CF_ACCESS_CLIENT_SECRET:-}" ]; then
  CFH=(-H "CF-Access-Client-Id: $CF_ACCESS_CLIENT_ID" -H "CF-Access-Client-Secret: $CF_ACCESS_CLIENT_SECRET")
fi
c() { curl -s -A "$UA" --max-time 15 "${CFH[@]}" "$@"; }
c_sin_token() { curl -s -A "$UA" --max-time 15 "$@"; }   # para http:// — el token nunca viaja sin TLS

H=$(c -k -I "$URL/")
echo "# En vivo (nivel 1, pasivo) — $URL — $(date '+%Y-%m-%d %H:%M')"

# --- Cloudflare Access -------------------------------------------------------------------------
ACCESS=0
if echo "$H" | grep -qiE '^location: .*cloudflareaccess\.com|^www-authenticate: Cloudflare-Access'; then
  ACCESS=1
  echo; echo "🔒 **Protegido por Cloudflare Access.** Sin sesión de Access no se llega a la app: los headers y"
  echo "   cookies de abajo son de la pantalla de Access, no de tu aplicación. Para revisar la app hace falta"
  echo "   un service token de Access o correr la suite desde dentro (local/staging)."
elif [ ${#CFH[@]} -gt 0 ] && echo "$H" | head -1 | grep -qE ' (401|403)' && \
     c_sin_token -k -I "$URL/" | grep -qiE '^location: .*cloudflareaccess\.com'; then
  ACCESS=1
  echo; echo "❌ **Access rechazó el service token** (¿caducó, o la política de la app no tiene una regla \"Service Auth\" que lo incluya?)."
  echo "   Lo de abajo sigue siendo la pantalla de Access."
elif [ ${#CFH[@]} -gt 0 ]; then
  echo; echo "🔑 Entrando con service token de Access: lo de abajo es la app real."
fi

# --- HTTPS (chequeo 16) -------------------------------------------------------------------------
echo; echo "## HTTPS (chequeo 16)"
if [[ $URL == https://* ]]; then
  read -r code loc < <(c_sin_token -o /dev/null -w "%{http_code} %{redirect_url}" "http://$HOST/")
  if [[ $code =~ ^30[1278]$ && $loc == https://* ]]; then
    echo "- ✅ http://$HOST/ → $code a $loc"
  else
    echo "- ❌ **http://$HOST/ NO redirige a https** (responde $code${loc:+ → $loc}). Activa \"Always Use HTTPS\" o una redirección 301."
  fi
  if c -o /dev/null "https://$HOST/"; then echo "- ✅ Certificado TLS válido"; else echo "- ❌ **Certificado TLS inválido o con error**"; fi
else
  echo "- La URL es http:// (normal en local; en producción es falla del chequeo 16)"
fi

# --- Headers (chequeo 17) -----------------------------------------------------------------------
echo; echo "## Headers de seguridad (chequeo 17)"
for h in content-security-policy strict-transport-security x-content-type-options referrer-policy permissions-policy x-frame-options; do
  v=$(echo "$H" | grep -i "^$h:" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ //')
  if [ -n "$v" ]; then echo "- ✅ $h: ${v:0:110}"
  elif [ $h = x-frame-options ] && echo "$H" | grep -qi 'frame-ancestors'; then echo "- ✅ x-frame-options: cubierto por CSP frame-ancestors"
  elif [ $ACCESS = 1 ]; then echo "- ℹ️ $h: no visible (pantalla de Access)"
  else echo "- ❌ falta $h"; fi
done
for h in server x-powered-by; do
  v=$(echo "$H" | grep -i "^$h:" | head -1 | cut -d: -f2- | tr -d '\r' | sed 's/^ //')
  [ -z "$v" ] && continue
  if echo "$v" | grep -qE '[0-9]+\.[0-9]+'; then echo "- ⚠️ $h revela versión: $v"; else echo "- ℹ️ $h: $v (sin versión)"; fi
done

# --- Cookies (chequeo 18) -----------------------------------------------------------------------
echo; echo "## Cookies de la página principal (chequeo 18)"
n=0
while IFS= read -r ck; do
  n=1; nombre=$(echo "$ck" | sed -E 's/^set-cookie: *([^=]+)=.*/\1/I')
  falta=""; for f in HttpOnly Secure SameSite; do echo "$ck" | grep -qi "$f" || falta="$falta $f"; done
  if [ -n "$falta" ]; then echo "- ⚠️ $nombre → falta:$falta"; else echo "- ✅ $nombre → HttpOnly, Secure, SameSite"; fi
done < <(echo "$H" | grep -i '^set-cookie:' | tr -d '\r')
[ $n = 0 ] && echo "- (no pone cookies sin sesión)"

# --- Rutas sensibles (chequeos 3, 19, 20) -------------------------------------------------------
echo; echo "## Rutas sensibles (chequeos 3, 19, 20)"
if [ $ACCESS = 1 ]; then echo "- Omitido: todo pasa por Cloudflare Access."; exit 0; fi

# Página comodín: muchas SPA devuelven 200 con el mismo HTML para cualquier ruta.
read -r bcode bsize < <(c -o "$TMP/base" -w "%{http_code} %{size_download}" "$URL/no-existe-ss-$RANDOM$RANDOM")
[ "$bcode" = 200 ] && echo "- ℹ️ Una ruta inexistente responde 200 (${bsize} bytes): el sitio tiene página comodín; se compara contenido."

# firma esperada por ruta (regex sobre los primeros bytes); vacía = basta con que no sea la página comodín
declare -A FIRMA=(
  [/.env]='^[A-Za-z_][A-Za-z0-9_]*=' [/.git/HEAD]='^ref: refs/' [/.git/config]='\[core\]'
  [/db.sqlite]='SQLite format 3' [/backup.zip]='^PK' [/.DS_Store]='Bud1' [/openapi.json]='"openapi"|"swagger"'
  [/swagger.json]='"swagger"|"openapi"' [/phpinfo.php]='phpinfo\(\)|PHP Version' [/server-status]='Server Status'
  [/docs]='swagger-ui|SwaggerUI' [/redoc]='redoc' [/config.json]='^\s*[\{\[]' [/debug]='' [/admin]='' [/api/admin]=''
  [/graphql]='' [/actuator]='' [/wp-admin]=''
)
for p in /.env /.git/HEAD /.git/config /db.sqlite /backup.zip /.DS_Store /config.json /openapi.json /swagger.json /docs /redoc \
         /debug /phpinfo.php /server-status /admin /api/admin /graphql /actuator /wp-admin; do
  read -r code size < <(c -o "$TMP/r" -w "%{http_code} %{size_download}" "$URL$p")
  if [ "$code" != 200 ]; then
    case $code in 30*) m="redirige";; 401|403) m="protegida ✅";; 404|410) m="no existe ✅";; *) m="";; esac
    echo "- $p → $code $m"; continue
  fi
  firma="${FIRMA[$p]}"
  if [ -n "$firma" ]; then
    if head -c 4096 "$TMP/r" | LC_ALL=C grep -qaE "$firma"; then echo "- ❌ **$p EXPUESTA** (200 y el contenido coincide con el tipo de archivo)"
    else echo "- $p → 200 pero no es el archivo real (página comodín/HTML) ✅"; fi
  else
    if [ "$bcode" = 200 ] && [ -n "$bsize" ] && [ "$bsize" -gt 0 ] && [ $(( (size - bsize) * 100 / bsize )) -ge -3 ] && [ $(( (size - bsize) * 100 / bsize )) -le 3 ]; then
      echo "- $p → 200 igual que la página comodín ✅"
    else
      echo "- ⚠️ $p → 200 con contenido propio (${size} bytes): revisar a mano si debe ser público"
    fi
  fi
done
sec=$(c -o /dev/null -w "%{http_code}" "$URL/.well-known/security.txt")
[ "$sec" = 200 ] && echo "- ✅ /.well-known/security.txt existe" || echo "- ℹ️ sin /.well-known/security.txt (recomendado)"
exit 0
