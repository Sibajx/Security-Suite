#!/usr/bin/env bash
# Prueba de supabase-rls.py: estático sobre el fixture Next.js y en vivo contra un PostgREST falso (sin red).
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; S="$R/skills/security-suite/scripts/supabase-rls.py"
T=$(mktemp -d); PUERTO=${PUERTO:-8796}
bash "$R/tests/crear-fixture-next.sh" "$T/fxn" >/dev/null
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
tiene() { grep -q -- "$2" "$T/est.md" && echo "✅ $1" || { echo "❌ $1 (no aparece «$2»)"; fallas=$((fallas+1)); }; }

python3 "$S" "$T/fxn" --publicas productos > "$T/est.md"; chk "fixture Next: falla (sale 1)" "$?" 1
tiene "tabla pedidos sin RLS" 'tabla `pedidos` sin'
tiene "rol desde user_metadata" "user_metadata"
tiene "service_role en variable pública" "NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY"
tiene "mensajes abierta a cualquier usuario" "«mensajes»"
tiene "security definer sin search_path" "search_path"
grep -q "catalogo publico" "$T/est.md" && { echo "❌ marcó el catálogo declarado público"; fallas=$((fallas+1)); } || echo "✅ no marca el catálogo con --publicas"
grep "profiles" "$T/est.md" | grep -v "Tablas conocidas" | grep -q . && { echo "❌ marcó profiles"; fallas=$((fallas+1)); } || echo "✅ no marca profiles (RLS por auth.uid)"

mkdir -p "$T/bien/supabase/migrations"
printf 'create table public.notas (id int, usuario uuid);\nalter table public.notas enable row level security;\ncreate policy "mias" on public.notas for select using (usuario = auth.uid());\n' > "$T/bien/supabase/migrations/1.sql"
python3 "$S" "$T/bien" >/dev/null; chk "proyecto con RLS correcta: sale 0" "$?" 0
mkdir -p "$T/nada"; python3 "$S" "$T/nada" >/dev/null; chk "sin Supabase ni Firebase: sale 2" "$?" 2

cat > "$T/srv.py" <<'PY'
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
FILAS = {"pedidos": 42, "notas": 0, "productos": 7}
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_HEAD(self):
        tabla = self.path.split("/rest/v1/")[-1].split("?")[0]
        anon = self.headers.get("Authorization") == "Bearer anon-falsa"
        if tabla not in FILAS: self.send_response(404); self.end_headers(); return
        n = FILAS[tabla] if (anon or tabla != "notas") else 3
        if self.headers.get("Prefer") != "count=exact" or self.command != "HEAD": self.send_response(400); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Range", f"*/{n}"); self.end_headers()
    def do_GET(self):  # nunca debe llamarse: el script solo hace HEAD
        self.send_response(500); self.end_headers()
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$T/srv.py" "$PUERTO" & SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PUERTO), 1)" 2>/dev/null && break; sleep 0.1; done
U="http://127.0.0.1:$PUERTO"
SUPABASE_ANON_KEY=anon-falsa TOKEN_A=token-a python3 "$S" "$T/bien" --url "$U" --nivel 2 --tablas pedidos,productos --publicas productos > "$T/vivo.md"
chk "en vivo: anónimo ve filas de pedidos → sale 1" "$?" 1
grep -q "un anónimo ve \*\*42\*\* filas" "$T/vivo.md" && echo "✅ reporta el conteo de pedidos" || { echo "❌ no reportó el conteo"; fallas=$((fallas+1)); }
grep -q "pública a propósito (7 filas)" "$T/vivo.md" && echo "✅ productos pública a propósito" || { echo "❌ productos"; fallas=$((fallas+1)); }
grep -q '`notas` | 200 | 0 | 3' "$T/vivo.md" && echo "✅ notas: 0 para anónimo, 3 para la cuenta A" || { echo "❌ notas"; fallas=$((fallas+1)); }
SUPABASE_ANON_KEY=anon-falsa python3 "$S" "$T/bien" --url "$U" >/dev/null 2>&1; chk "en vivo sin nivel 2: se niega (2)" "$?" 2
python3 "$S" "$T/bien" --url "$U" --nivel 2 >/dev/null 2>&1; chk "en vivo sin anon key: no se pudo (2)" "$?" 2
exit $fallas
