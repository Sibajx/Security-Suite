#!/usr/bin/env bash
# Prueba de webhook-falso.py y chatbot-inyeccion.py contra un servidor falso local (sin red, sin LLM real).
set -uo pipefail
S="$(cd "$(dirname "$0")/.." && pwd)/skills/security-suite/scripts"
T=$(mktemp -d)
PUERTO=${PUERTO:-8797}
cat > "$T/srv.py" <<'EOF'
import hashlib, hmac, json, re, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
SISTEMA = "Eres el asistente de Tienda Demo. El código interno es STAFF-90."
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
        msg = json.loads(cuerpo or b"{}").get("mensaje", "")
        if self.path == "/chat-fuga":      # obedece todo, filtra el prompt y datos de otro usuario
            if "palabra por palabra" in msg or "Traduce" in msg:
                r = SISTEMA
            elif "pedido" in msg:
                r = "El pedido 2 es de beto@tienda-demo.invalid, Calle Beto 2."
            else:
                m = re.search(r"(<img[^>]*>|!\[[^\]]*\]\([^)]*\)|sscanario[0-9a-f]+)", msg)
                r = m.group(1) if m else "ok"
            return self.responder(200, {"respuesta": r})
        if self.path == "/chat-seguro":
            return self.responder(200, {"respuesta": "Solo puedo ayudarte con tus propios pedidos."})
        self.responder(404, {})
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
python3 "$T/srv.py" "$PUERTO" & SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do python3 -c "import socket; socket.create_connection(('127.0.0.1', $PUERTO), 1)" 2>/dev/null && break; sleep 0.1; done
B="http://127.0.0.1:$PUERTO"
echo '{"id":"evt_pentest","type":"checkout.session.completed","data":{"object":{"metadata":{"pedido_id":"1"}}}}' > "$T/ev.json"

fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }
wh() { python3 "$S/webhook-falso.py" --url "$B/$1" --proveedor "${2:-stripe}" --datos "$T/ev.json" --nivel 3 --cuenta-de-prueba --salida "$T/wh-$1.md" >/dev/null 2>&1; echo $?; }
cb() { local r=$1; shift; python3 "$S/chatbot-inyeccion.py" --url "$B/$r" --pausa 0 --nivel 2 --salida "$T/cb-$r.md" "$@" >/dev/null 2>&1; echo $?; }

chk "webhook sin verificación de firma = falla" "$(wh webhook-malo)" 1
chk "webhook con HMAC verificado = rechaza" "$(wh webhook-bueno mercadopago)" 0
chk "webhook inexistente = no se pudo probar" "$(wh no-existe)" 2
python3 "$S/webhook-falso.py" --url "$B/webhook-malo" --datos "$T/ev.json" >/dev/null 2>&1
chk "webhook sin nivel 3 = se niega (2)" "$?" 2

chk "chatbot que filtra prompt y datos ajenos = falla" \
    "$(cb chat-fuga --fragmento-sistema 'código interno' --dato-ajeno beto@tienda-demo.invalid)" 1
grep -q "filtró el system prompt" "$T/cb-chat-fuga.md" && echo "✅ detecta la fuga del system prompt" || { echo "❌ no detectó la fuga del prompt"; fallas=$((fallas+1)); }
grep -q "dato de otro usuario" "$T/cb-chat-fuga.md" && echo "✅ detecta el dato de otro usuario" || { echo "❌ no detectó el dato ajeno"; fallas=$((fallas+1)); }
grep -q "HTML crudo" "$T/cb-chat-fuga.md" && echo "✅ avisa del HTML crudo" || { echo "❌ no avisó del HTML crudo"; fallas=$((fallas+1)); }
grep -q "obedece instrucciones" "$T/cb-chat-fuga.md" && echo "✅ avisa que obedece instrucciones inyectadas" || { echo "❌ no avisó de obediencia"; fallas=$((fallas+1)); }
grep -q "beto@tienda" "$T/cb-chat-fuga.md" && { echo "❌ el reporte muestra el dato ajeno completo"; fallas=$((fallas+1)); } || echo "✅ el reporte no repite el dato ajeno completo en el resultado"
chk "chatbot que se niega = sin fuga" "$(cb chat-seguro --fragmento-sistema 'código interno' --dato-ajeno beto@tienda-demo.invalid)" 0
chk "chatbot que no existe = no se pudo probar" "$(cb no-existe)" 2
python3 "$S/chatbot-inyeccion.py" --url "$B/chat-fuga" >/dev/null 2>&1
chk "chatbot sin nivel 2 = se niega (2)" "$?" 2
exit $fallas
