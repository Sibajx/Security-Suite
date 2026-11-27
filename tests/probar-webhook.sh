#!/usr/bin/env bash
# Prueba de webhook-falso.py contra un servidor falso local (sin red).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/skills/security-suite/scripts"
T=$(mktemp -d)
PUERTO=${PUERTO:-8797}
cat > "$T/srv.py" <<'PY'
import hashlib, hmac, json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def responder(self, codigo, datos):
        b = json.dumps(datos).encode()
        self.send_response(codigo); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_POST(self):
        cuerpo = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/webhook-malo":
            return self.responder(200, {"recibido": True})
        if self.path == "/webhook-bueno":
            esperada = hmac.new(b"secreto-de-prueba", cuerpo, hashlib.sha256).hexdigest()
            ok = hmac.compare_digest(esperada, self.headers.get("x-firma", ""))
            return self.responder(200 if ok else 401, {"recibido": ok})
        self.responder(404, {})
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 "$T/srv.py" "$PUERTO" & SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PUERTO), 1)" 2>/dev/null && break; sleep 0.1; done
B="http://127.0.0.1:$PUERTO"
echo '{"id":"evt_pentest","type":"checkout.session.completed","data":{"object":{"metadata":{"pedido_id":"1"}}}}' > "$T/ev.json"

fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
wh() { python3 "$S/webhook-falso.py" --url "$B/$1" --proveedor "${2:-stripe}" --datos "$T/ev.json" --nivel 3 --cuenta-de-prueba --salida "$T/wh-$1.md" >/dev/null 2>&1; echo $?; }

chk "webhook sin verificación de firma = falla" "$(wh webhook-malo)" 1
chk "webhook con HMAC verificado = rechaza" "$(wh webhook-bueno mercadopago)" 0
chk "webhook inexistente = no se pudo probar" "$(wh no-existe)" 2
python3 "$S/webhook-falso.py" --url "$B/webhook-malo" --datos "$T/ev.json" >/dev/null 2>&1
chk "webhook sin nivel 3 = se niega (2)" "$?" 2
exit $fallas
