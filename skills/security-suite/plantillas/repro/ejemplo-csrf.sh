#!/usr/bin/env bash
# ID: P8
# (Ejemplo: app con login de dueño y panel /admin; copia la forma, no el contenido.)
# TITULO: POST del dueño aceptado desde otro origen (CSRF; otro *.ejemplo.com cuenta como mismo sitio)
# SEVERIDAD: MEDIA
# NIVEL: 3
# ESCRIBE: si
# REQUIERE: BASE PW_DUENO
# BASE: http://localhost:18803
set -u
J=$(mktemp); trap 'rm -f $J' EXIT
c=$(curl -s -o /dev/null -w "%{http_code}" -c $J --data-urlencode "usuario=dueno" --data-urlencode "password=$PW_DUENO" "$BASE/auth/login")
grep -q sesion $J || { echo "no se pudo entrar como dueño ($c)"; exit 2; }
malos=0
for h in "Origin: https://otro.ejemplo.com|Sec-Fetch-Site: same-site" "Origin: https://evil.example|Sec-Fetch-Site: cross-site" "Origin: https://evil.example|X-Nada: 1"; do
  r=$(curl -s -o /dev/null -w "%{http_code}" -b $J -H "${h%%|*}" -H "${h##*|}" -d "nombre=pentest csrf&dias=0&desde=00:00&hasta=23:59" "$BASE/admin/promos")
  echo "${h%%|*} -> $r"; [ "$r" = 403 ] || malos=$((malos+1))
done
r=$(curl -s -o /dev/null -w "%{http_code}" -b $J -d "nombre=pentest control&dias=0&desde=00:00&hasta=23:59" "$BASE/admin/promos")
echo "control sin Origin -> $r"; [ "$r" = 303 ] || { echo "el control no pasó: no concluyente"; exit 2; }
echo "$malos de 3 envíos desde otro origen aceptados"
exit $(( malos > 0 ))
