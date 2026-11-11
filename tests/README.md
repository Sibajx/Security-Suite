# Pruebas de la suite

La suite se mide contra una app FastAPI con 28 fallas plantadas y 5 trampas.

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
