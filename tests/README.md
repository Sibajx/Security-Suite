# Pruebas de la suite

La suite se mide contra una app FastAPI con 31 fallas plantadas y 6 trampas.

```bash
# 1. Crear el fixture (las claves falsas se generan al vuelo; ningún secreto vive en este repo)
bash tests/crear-fixture.sh /tmp/fixture-ss

# 2. Levantarlo en http://127.0.0.1:8765 (necesita uv)
bash tests/levantar-fixture.sh /tmp/fixture-ss

# 3. En Claude Code, desde cualquier carpeta:
#    "Usa security-suite en modo completo sobre /tmp/fixture-ss, URL http://127.0.0.1:8765, entorno local,
#     es mío, cuentas ana@tienda-demo.invalid / ana-demo-123 y beto@tienda-demo.invalid / beto-demo-123"

# 4. Comparar el DIAGNOSTICO.md con tests/esperado.md
```

Úsalo cada vez que cambies un agente, el SKILL.md o un script, y para comparar modelos.

## Calificar automáticamente (calidad y tokens)

```bash
# Recall, trampas, secretos filtrados y tokens de la corrida (transcripciones de Claude Code, incluidas las de subagentes)
python3 tests/calificar.py <Reportes-securitysuite>/<sitio>_RSS/<fecha> --fixture /tmp/fixture-ss \
  --transcript ~/.claude/projects/<proyecto>/<sesion>.jsonl ~/.claude/projects/<proyecto>/<sesion>/subagents/*.jsonl
```
Pega la fila que imprime en «Resultados registrados» de `esperado.md`. Antes de aceptar un cambio que ahorra tokens,
compara: el recall no debe bajar y las trampas deben seguir en 0.

## App Next.js + Supabase (modo `rapido-ia`, solo estático)

```bash
bash tests/crear-fixture-next.sh /tmp/fixture-next
# En Claude Code: "revisión rápida de /tmp/fixture-next, la hice con IA, no hay URL"
python3 tests/calificar.py <carpeta-del-reporte> --esperado tests/esperado-next.json
```

## Pruebas de los scripts (las corre el CI)

`probar-reverificar.sh`, `probar-revisar-access.sh`, `probar-webhook.sh`, `probar-supabase-rls.sh`,
`probar-calificar.sh`, `probar-utilidades.sh` (sin red) y `probar-semgrep.sh` (necesita `pip install semgrep`).
