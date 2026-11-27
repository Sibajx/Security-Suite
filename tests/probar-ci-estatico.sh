#!/usr/bin/env bash
# Prueba de ci-estatico.sh (barrera de CI sin modelo): bloquea un proyecto con fallas, pasa uno limpio.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; C="$R/skills/security-suite/scripts/ci-estatico.sh"
export PATH="$HOME/.local/bin:$PATH"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fallas=0
chk() { [ "$2" = "$3" ] && echo "✅ $1" || { echo "❌ $1 (salió $2, esperaba $3)"; fallas=$((fallas+1)); }; }

# Proyecto con webhook sin firma (semgrep ERROR) → debe bloquear
mkdir -p "$T/malo/app/api/webhooks/stripe"
cat > "$T/malo/app/api/webhooks/stripe/route.ts" <<'TS'
export async function POST(req) { const e = await req.json(); await db.pagar(e.pedidoId); return Response.json({ok:true}); }
TS
bash "$C" "$T/malo" --salida "$T/malo.md" >/dev/null 2>&1; chk "proyecto con webhook sin firma: bloquea (1)" "$?" 1
grep -q "bloqueante" "$T/malo.md" && echo "✅ el informe marca el bloqueo" || { echo "❌ informe sin bloqueo"; fallas=$((fallas+1)); }

# Proyecto limpio → pasa
mkdir -p "$T/limpio"; echo "print('hola')" > "$T/limpio/app.py"
bash "$C" "$T/limpio" >/dev/null 2>&1; chk "proyecto limpio: pasa (0)" "$?" 0
exit $fallas
