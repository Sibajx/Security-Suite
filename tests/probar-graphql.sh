#!/usr/bin/env bash
# Prueba de graphql-revisar.py: estático (config insegura vs segura) y en vivo contra un servidor GraphQL falso.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; S="$R/skills/security-suite/scripts/graphql-revisar.py"
T=$(mktemp -d); PUERTO=${PUERTO:-8793}
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
tiene() { grep -q -- "$2" "$1" && echo "✅ $3" || { echo "❌ $3"; fallas=$((fallas+1)); }; }

mkdir -p "$T/mal/src" "$T/bien/src" "$T/nada"
cat > "$T/mal/src/server.ts" <<'EOF'
import { ApolloServer } from "@apollo/server";
const server = new ApolloServer({ typeDefs, resolvers, introspection: true, playground: true });
EOF
cat > "$T/bien/src/server.ts" <<'EOF'
import { ApolloServer } from "@apollo/server";
import depthLimit from "graphql-depth-limit";
const server = new ApolloServer({ typeDefs, resolvers, introspection: false, validationRules: [depthLimit(7)] });
EOF
echo "console.log(1)" > "$T/nada/app.js"

python3 "$S" "$T/mal" --salida "$T/mal.md" >/dev/null; chk "config insegura = falla (1)" "$?" 1
tiene "$T/mal.md" "introspección activada" "detecta introspection: true"
tiene "$T/mal.md" "límite de profundidad" "detecta la falta de límite de profundidad"
tiene "$T/mal.md" "playground" "detecta el playground activo"
python3 "$S" "$T/bien" >/dev/null; chk "config segura = 0" "$?" 0
python3 "$S" "$T/nada" >/dev/null 2>&1; chk "sin GraphQL ni --url = no se pudo (2)" "$?" 2

cat > "$T/srv.py" <<'PY'
import sys, json
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        b = json.dumps({"data": {"__schema": {"types": [{"name": "Pedido"}], "queryType": {"fields": []}}}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$T/srv.py" "$PUERTO" & SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PUERTO), 1)" 2>/dev/null && break; sleep 0.1; done
python3 "$S" "$T/bien" --url "http://127.0.0.1:$PUERTO/graphql" --nivel 2 --salida "$T/vivo.md" >/dev/null; chk "en vivo con introspección abierta = falla (1)" "$?" 1
tiene "$T/vivo.md" "introspección abierta en vivo" "reporta introspección abierta en vivo"
tiene "$T/vivo.md" "sin límite de profundidad" "reporta la consulta profunda aceptada"
python3 "$S" "$T/bien" --url "http://127.0.0.1:$PUERTO/graphql" >/dev/null 2>&1; chk "en vivo sin nivel 2 = se niega (2)" "$?" 2
exit $fallas
