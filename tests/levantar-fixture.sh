#!/usr/bin/env bash
# Levanta el fixture en http://127.0.0.1:${PUERTO:-8765} con dependencias actuales (para el pentest).
# Uso: bash tests/levantar-fixture.sh <directorio-del-fixture>
# Cuentas de prueba: ana@tienda-demo.invalid / ana-demo-123 · beto@tienda-demo.invalid / beto-demo-123
set -euo pipefail
cd "${1:?uso: levantar-fixture.sh <fixture>}"
[ -d .venv-run ] || { uv venv -q .venv-run && uv pip install -q -p .venv-run fastapi uvicorn jinja2 requests pyyaml openai python-multipart; }
.venv-run/bin/python app/init_db.py
# Entorno LIMPIO: el fixture tiene un /debug que devuelve os.environ; nunca debe ver tus variables reales.
exec env -i PATH=/usr/bin:/bin HOME="$PWD" OPENAI_API_KEY=sk-falsa-solo-para-arrancar .venv-run/bin/uvicorn app.main:app --host 127.0.0.1 --port "${PUERTO:-8765}"
