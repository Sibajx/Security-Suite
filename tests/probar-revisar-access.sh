#!/usr/bin/env bash
# Prueba de revisar-access.py con el error típico (PIN en Include junto a correos) y sus variantes. Sin red.
S="$(cd "$(dirname "$0")/.." && pwd)/skills/security-suite/scripts/revisar-access.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
correos='{"email":{"email":"a@x.com"}},{"email":{"email":"b@x.com"}}'
caso() { echo "{\"apps\":[{\"name\":\"$1\",\"domain\":\"d\",\"type\":\"self_hosted\",\"policies\":[{\"name\":\"p\",\"decision\":\"allow\",\"include\":[$2],\"require\":[$3]}]}],\"grupos\":[{\"id\":\"g1\",\"name\":\"todos\",\"include\":[{\"everyone\":{}}]},{\"id\":\"g2\",\"name\":\"equipo\",\"include\":[$correos]}]}" > "$T/$1.json"; python3 "$S" "$T/$1.json" >/dev/null; echo $?; }
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
chk "PIN en Include junto a correos = abierta (error típico)" "$(caso pin_include "{\"auth_method\":{\"auth_method\":\"pin\"}},$correos" "")" 1
chk "login_method en Include = abierta" "$(caso login "{\"login_method\":{\"id\":\"x\"}},$correos" "")" 1
chk "solo correos = cerrada" "$(caso correos "$correos" "")" 0
chk "PIN en Require con correos en Include = cerrada" "$(caso require "$correos" "{\"auth_method\":{\"auth_method\":\"pin\"}}")" 0
chk "Everyone con Require de correo = cerrada" "$(caso req2 "{\"everyone\":{}}" "{\"email\":{\"email\":\"a@x.com\"}}")" 0
chk "dominio gmail.com = abierta" "$(caso gmail "{\"email_domain\":{\"domain\":\"gmail.com\"}}" "")" 1
chk "grupo con Everyone = abierta" "$(caso grupo "{\"group\":{\"id\":\"g1\"}}" "")" 1
chk "grupo de correos = cerrada" "$(caso grupo2 "{\"group\":{\"id\":\"g2\"}}" "")" 0
echo '{"apps":[{"name":"pub","domain":"p","type":"self_hosted","policies":[{"name":"publico","decision":"bypass","include":[{"everyone":{}}]}]}]}' > "$T/b.json"
python3 "$S" "$T/b.json" > "$T/b.md"; c=$?
chk "bypass público: no es error (sale 0)" "$c" 0
grep -q "pública a propósito" "$T/b.md" && echo "✅ bypass se reporta como público a propósito" || { echo "❌ bypass sin etiqueta"; fallas=$((fallas+1)); }
exit $fallas
