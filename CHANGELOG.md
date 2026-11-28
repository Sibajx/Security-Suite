# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es/). Versiones [SemVer](https://semver.org/lang/es/).

## [1.3.0] — 2026-11-27

### Agregado
- **GraphQL (X13)**: chequeo nuevo y `scripts/graphql-revisar.py` (estático: introspección, límite de profundidad,
  playground; en vivo, sin extraer datos: introspección y una consulta anidada benigna).
- **Medición de tokens**: `tests/medir-lectura.py` compara el contexto que lee cada auditor entre dos versiones.
  La v1.2 lee **83% menos** que la v1.1 (`docs/medicion-tokens.md`).
- **Fixture Django + DRF** (`tests/crear-fixture-django.sh`, `tests/esperado-django.json`), con corrida real de los
  3 auditores calificada 20/20 (`docs/ejemplo-django.md`). Tercer stack, para comprobar que los auditores generalizan.
- **Pentest en vivo en CI** (`tests/probar-pentest-vivo.sh` + job `pentest-vivo`): levanta el fixture FastAPI y corre
  las herramientas en vivo.
- **GitHub Action reutilizable** (`action.yml` + `scripts/ci-estatico.sh`, `docs/accion-ci.md`): barrera de CI sin
  modelo (secretos, reglas de semgrep, Supabase, GraphQL).

### Corregido
- `calificar.py`: ya no excluye una sección por mencionar «trampas» de pasada; separa tokens nuevos de la caché leída.
- `medir-lectura.py`: detecta una ref de git faltante (checkout shallow) y sale 2 en vez de dar un resultado engañoso.

## [1.2.0] — 2026-11-26

### Agregado
- Menos tokens: `resumir-escaneo.py` (escaneo-compacto.md), `chequeos.py` (cada agente lee solo sus chequeos),
  guías OWASP a demanda (`owasp/INDICE.md`), modo `incremental` (`cambios-desde.py`) y presupuesto `economico`.
- `supabase-rls.py`: RLS, `using (true)`, rol desde `user_metadata`, service_role pública; en vivo cuenta filas.
- 8 reglas nuevas de semgrep (precio del cliente, IDOR Supabase/Prisma, redirect abierto, service_role pública,
  webhook en Next.js), más el open redirect del lado del cliente.
- Medición de calidad: `tests/calificar.py` (recall, trampas, secretos filtrados, tokens).
- Fixture Next.js + Supabase + Stripe; plantillas de arreglo para Next.js y Express.

## [1.1.0] — 2026-11-26

### Agregado
- Los 15 ataques típicos a una app hecha con IA: X10 webhooks de pago, X11 funciones con LLM, X12 respaldos contra
  ransomware; ajustes a 11 (códigos cortos), X4 (precio y cupones) y X6 (logs fuera del servidor).
- `webhook-falso.py`, reglas propias de semgrep (corren sin red) y modo `rapido-ia` (`rapido-app-ia.md`).

## [1.0.0] — 2026-11-26

- Versión inicial: 20 chequeos + extras, 3 auditores, pentester, verificador, diagnóstico y tratamiento.
