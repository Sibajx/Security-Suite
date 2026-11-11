#!/usr/bin/env bash
# Seguridad de correo y DNS de un dominio: SPF, DMARC, DKIM, MX, CAA, DNSSEC.
# Solo consultas DNS públicas. Uso: bash correo-dns.sh <dominio>
set -uo pipefail
D="${1:?uso: correo-dns.sh <dominio>}"; D=$(echo "$D" | sed -E 's#^[a-z]+://##; s#/.*$##')
q() { dig +short +time=3 +tries=1 "$@" 2>/dev/null; }

echo "# Correo y DNS — $D — $(date '+%Y-%m-%d %H:%M')"
echo
echo "## Correo (suplantación de tu dominio)"
mx=$(q "$D" MX | sort -n | tr '\n' ' ')
echo "- MX: ${mx:-ninguno (el dominio no recibe correo)}"

spf=$(q "$D" TXT | tr -d '"' | grep -i '^v=spf1' | head -1)
if [ -z "$spf" ]; then echo "- ❌ **Sin SPF**: cualquiera puede mandar correo como @$D sin que falle SPF. Si el dominio no envía correo: \`v=spf1 -all\`."
elif echo "$spf" | grep -q -- '-all'; then echo "- ✅ SPF estricto: \`$spf\`"
elif echo "$spf" | grep -q -- '~all'; then echo "- ⚠️ SPF en softfail (~all): \`$spf\` — aceptable si DMARC está en quarantine/reject."
else echo "- ❌ **SPF permisivo** (\`?all\`/\`+all\` o sin all): \`$spf\`"; fi
n_lookups=$(echo "$spf" | grep -oE 'include:|a[: ]|mx[: ]|ptr|exists:|redirect=' | wc -l)
[ "$n_lookups" -gt 10 ] && echo "- ❌ SPF con $n_lookups consultas DNS (máximo 10): falla con permerror."

dmarc=$(q "_dmarc.$D" TXT | tr -d '"' | grep -i '^v=DMARC1' | head -1)
if [ -z "$dmarc" ]; then echo "- ❌ **Sin DMARC**: los correos falsos con tu dominio llegan a la bandeja de entrada. Empezar con \`v=DMARC1; p=quarantine; rua=mailto:…\`."
else
  p=$(echo "$dmarc" | grep -oiE 'p=[a-z]+' | head -1 | cut -d= -f2)
  case "$p" in
    reject) echo "- ✅ DMARC p=reject: \`$dmarc\`" ;;
    quarantine) echo "- ✅ DMARC p=quarantine (subir a reject cuando los reportes estén limpios): \`$dmarc\`" ;;
    *) echo "- ⚠️ **DMARC p=none** (solo monitorea, no protege): \`$dmarc\` → pasar a \`p=quarantine\` y luego \`p=reject\`." ;;
  esac
fi

encontrados=""
for s in default google selector1 selector2 k1 k2 resend brevo mail dkim s1 s2 smtp cf mailo zoho protonmail protonmail2 mandrill sendgrid; do
  v=$(q "$s._domainkey.$D" TXT | tr -d '"' | grep -iE 'v=DKIM1|p=' | head -1)
  [ -z "$v" ] && v=$(q "$s._domainkey.$D" CNAME | head -1)
  [ -n "$v" ] && encontrados="$encontrados $s"
done
if [ -n "$encontrados" ]; then echo "- ✅ DKIM encontrado (selectores:$encontrados)"
else echo "- ⚠️ DKIM: ningún selector común encontrado (puede usar uno propio; revísalo en tu proveedor de correo)."; fi

echo
echo "## DNS"
caa=$(q "$D" CAA | tr '\n' ' ')
[ -n "$caa" ] && echo "- ✅ CAA (quién puede emitir certificados): $caa" || echo "- ⚠️ Sin CAA: cualquier autoridad puede emitir certificados para $D. Ej.: \`0 issue \"letsencrypt.org\"\`, \`0 issue \"pki.goog\"\` (lo que usa Cloudflare)."
ds=$(q "$D" DS)
[ -n "$ds" ] && echo "- ✅ DNSSEC activo" || echo "- ⚠️ DNSSEC apagado (en Cloudflare: DNS → Settings → Enable DNSSEC y poner el DS en el registrador)."
ns=$(q "$D" NS | tr '\n' ' '); echo "- NS: $ns"
