#!/usr/bin/env bash
# Prueba de las utilidades que ahorran tokens: chequeos.py, resumir-escaneo.py y cambios-desde.py. Sin red.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; S="$R/skills/security-suite/scripts"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió «$2», esperaba «$3»)"; fallas=$((fallas+1)); }; }

# chequeos.py: cada agente recibe exactamente sus chequeos de la tabla «Reparto», y todos existen
for a in infra-secretos acceso entradas; do
  python3 "$S/chequeos.py" "$a" > "$T/$a.md"; chk "chequeos.py $a sale 0" "$?" 0
done
chk "acceso recibe X10 y no X11" "$(grep -c '^\*\*X10\.' "$T/acceso.md")$(grep -c '^\*\*X11\.' "$T/acceso.md")" "10"
chk "entradas recibe X11" "$(grep -c '^\*\*X11\.' "$T/entradas.md")" 1
total=$(python3 "$S/chequeos.py" --lista | wc -l); repartidos=$(cat "$T"/{infra-secretos,acceso,entradas}.md | grep -c '^\*\*X\?[0-9]*\. ')
chk "todos los chequeos tienen agente ($total)" "$repartidos" "$total"
python3 "$S/chequeos.py" X99 >/dev/null 2>&1; chk "chequeo inexistente sale 2" "$?" 2

# resumir-escaneo.py: agrupa, quita duplicados y no muestra secretos
mkdir -p "$T/p" "$T/ev"; printf 'a\nb = "sk-proj-abcdefghijklmnop1234"\n' > "$T/p/x.py"
cat > "$T/ev/semgrep.json" <<'J'
{"results":[{"check_id":"a.b.security-suite.webhook-sin-firma","path":"x.py","start":{"line":2},"extra":{"severity":"ERROR","message":"m"}},
{"check_id":"a.b.security-suite.webhook-sin-firma","path":"x.py","start":{"line":2},"extra":{"severity":"ERROR","message":"m"}}],"errors":[]}
J
echo '[{"RuleID":"r","File":".env","StartLine":1,"Commit":"abcdef123"},{"RuleID":"r","File":".env","StartLine":1,"Commit":"bcdef1234"}]' > "$T/ev/gitleaks-historial.json"
python3 "$S/resumir-escaneo.py" "$T/p" "$T/ev" >/dev/null; c="$T/ev/escaneo-compacto.md"
chk "semgrep: duplicado contado una vez" "$(grep -c '^- `x.py:2`' "$c")" 1
chk "regla local con nombre corto" "$(grep -c 'security-suite.webhook-sin-firma`' "$c")" 1
chk "gitleaks agrupa los 2 commits" "$(grep -c 'abcdef1 bcdef12' "$c")" 1
chk "no muestra el secreto completo" "$(grep -c 'abcdefghijklmnop1234' "$c")" 0

# cambios-desde.py: sin commit en la base → 2; base vieja → 3; cambio en webhook → acceso
mkdir -p "$T/g" && cd "$T/g" && git init -q -b main && git config user.email t@t.invalid && git config user.name t
mkdir -p api && echo x > api/webhook.ts && echo y > leeme.txt && git add -A && git commit -qm uno
c1=$(git rev-parse --short=10 HEAD); cd - >/dev/null
echo "**Fecha:** $(date +%F) · **Modo:** completo" > "$T/sin.md"
python3 "$S/cambios-desde.py" "$T/g" "$T/sin.md" >/dev/null 2>&1; chk "base sin commit sale 2" "$?" 2
echo "**Fecha:** 2020-01-01 · **Commit:** \`$c1\` · **Modo:** completo" > "$T/vieja.md"
python3 "$S/cambios-desde.py" "$T/g" "$T/vieja.md" >/dev/null; chk "base vieja sale 3" "$?" 3
echo "**Fecha:** $(date +%F) · **Commit:** \`$c1\` · **Modo:** completo" > "$T/base.md"
echo z >> "$T/g/api/webhook.ts"
python3 "$S/cambios-desde.py" "$T/g" "$T/base.md" > "$T/cambios.md"; chk "base reciente sale 0" "$?" 0
chk "el webhook va a acceso" "$(grep -c '^- \*\*acceso\*\* (1): `api/webhook.ts`' "$T/cambios.md")" 1
chk "infra-secretos se hereda" "$(grep -c 'se heredan sus resultados): infra-secretos' "$T/cambios.md")" 1

# matriz-permisos.py: nunca toca un GET marcado "escritura_ok": false ni un GET destructivo (incidente 2026-11-27)
cat > "$T/srv.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        open(sys.argv[2], "a").write(self.path + "\n")
        self.send_response(200); self.end_headers(); self.wfile.write(b"{}")
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
P=${PUERTO_MATRIZ:-8795}; python3 "$T/srv.py" "$P" "$T/visitas.log" & SRV=$!
for _ in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $P), 1)" 2>/dev/null && break; sleep 0.1; done
cat > "$T/matriz.json" <<J
{"base": "http://127.0.0.1:$P", "roles": {"anonimo": {}, "usuario_a": {}},
 "pruebas": [{"metodo": "GET", "ruta": "/pedidos/1", "permitidos": ["usuario_a"]},
             {"metodo": "GET", "ruta": "/cuenta/borrar", "permitidos": ["usuario_a"], "escritura_ok": false},
             {"metodo": "GET", "ruta": "/logout", "permitidos": ["usuario_a"]}]}
J
python3 "$S/matriz-permisos.py" "$T/matriz.json" --nivel 3 --rps 50 > "$T/matriz.md" 2>&1
kill $SRV 2>/dev/null
chk "matriz: visita la ruta de lectura" "$(grep -c '^/pedidos/1$' "$T/visitas.log")" 2
chk "matriz: NO visita GET /cuenta/borrar (escritura_ok false)" "$(grep -c 'borrar' "$T/visitas.log")" 0
chk "matriz: NO visita GET /logout (destructiva sin permiso)" "$(grep -c 'logout' "$T/visitas.log")" 0
exit $fallas
