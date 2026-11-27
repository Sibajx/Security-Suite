#!/usr/bin/env bash
# Prueba de las reglas propias de semgrep (semgrep/reglas-suite.yml) contra los dos fixtures y casos sueltos.
# Compara el conjunto exacto «regla archivo:línea»: si una regla deja de detectar o empieza a marcar algo seguro, falla.
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
command -v semgrep >/dev/null || { echo "semgrep no está instalado (pip install semgrep)"; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
bash "$R/tests/crear-fixture.sh" "$T/fx" >/dev/null
bash "$R/tests/crear-fixture-next.sh" "$T/fxn" >/dev/null
cp -r "$R/tests/semgrep" "$T/casos"
semgrep scan --config "$R/skills/security-suite/semgrep/reglas-suite.yml" --metrics=off --quiet --json \
  "$T/fx" "$T/fxn" "$T/casos" > "$T/r.json" 2>"$T/err" || true
python3 - "$T" <<'PY'
import json, sys
T = sys.argv[1]
d = json.load(open(f"{T}/r.json"))
obtenido = sorted({f"{r['check_id'].split('security-suite.')[-1]} {r['path'][len(T)+1:]}:{r['start']['line']}" for r in d["results"]})
esperado = sorted("""
webhook-sin-firma fx/app/main.py:239
codigo-con-random fx/app/main.py:269
llm-secreto-en-prompt fxn/app/api/chat/route.ts:10
precio-del-cliente fxn/app/api/checkout/route.ts:9
codigo-con-random-js fxn/app/api/otp/route.ts:6
supabase-por-id-sin-dueno fxn/app/api/pedidos/[id]/route.ts:5
redirect-abierto fxn/app/api/salir/route.ts:4
webhook-sin-firma-next fxn/app/api/webhooks/stripe/route.ts:4
supabase-por-id-sin-dueno fxn/app/api/webhooks/stripe/route.ts:8
llm-salida-a-html fxn/components/Chat.tsx:13
service-role-publica fxn/lib/supabase.ts:4
webhook-sin-firma casos/casos.py:5
codigo-con-random casos/casos.py:28
llm-secreto-en-prompt casos/casos.py:32
webhook-sin-firma-js casos/casos.js:1
llm-salida-a-html casos/casos.js:7
codigo-con-random-js casos/casos.js:9
prisma-por-id-sin-dueno casos/casos.ts:6
redirect-abierto-cliente casos/casos.ts:14
""".split("\n")[1:-1])
faltan, sobran = sorted(set(esperado) - set(obtenido)), sorted(set(obtenido) - set(esperado))
for x in esperado:
    print(("✅ " if x in obtenido else "❌ no detectó: ") + x)
for x in sobran:
    print("❌ falso positivo nuevo: " + x)
if d.get("errors"):
    print(f"❌ semgrep reportó {len(d['errors'])} errores: {d['errors'][0].get('message', '')[:200]}")
sys.exit(len(faltan) + len(sobran) + (1 if d.get("errors") else 0))
PY
