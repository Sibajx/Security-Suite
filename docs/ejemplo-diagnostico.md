# Diagnóstico de seguridad — tienda-demo (fixture de pruebas)

> Ejemplo real de salida de la suite sobre `tests/crear-fixture.sh` (app con fallas plantadas y datos falsos).

**Fecha:** 2026-11-09 · **Modo:** completo · **Objetivo en vivo:** http://127.0.0.1:8765 (local, nivel 3, autorizado por el usuario: sí)

## Veredicto

🔴 **NO DESPLEGAR**

**1/20 chequeos pasan** (X4 aparte) · CRÍTICAS: 11 · ALTAS: 13 · MEDIAS: 6 · confirmadas en vivo: 14

Cualquier persona en internet, sin cuenta, puede ejecutar código en el servidor (pickle/YAML, subida que sobrescribe
código con `--reload`), leer todas las claves (`/debug`), descargar la base de usuarios (inyección SQL y `/admin`
abierto) y volverse administradora al registrarse. Hay secretos de Stripe y de la base en el historial de git.

## Lo urgente (hacer hoy)

1. **Rotar** la clave de OpenAI, `STRIPE_SECRET` y la contraseña de la base — CRÍTICA — `frontend/src/config.js:2`, `.env` en el commit `inicio` — confirmado por código. Borrarlas no basta: siguen en git.
2. **Quitar `/debug`, `pickle.loads` y `yaml.load`** — CRÍTICA — `app/main.py:100,105,124` — confirmado en vivo.
3. **Parametrizar `/buscar`** — CRÍTICA — `app/main.py:57` — confirmado en vivo (UNION, sqlmap).
4. **Auth + rol en `/admin/usuarios`, filtro por dueño en `/pedidos`, sin `rol` en el registro** — CRÍTICA — `app/main.py:23-74` — confirmado en vivo.
5. **Subidas con nombre generado, tipo y tamaño** — CRÍTICA — `app/main.py:83-87` — confirmado en vivo (path traversal).

## Los 20 chequeos

| # | Chequeo | Estado | Hallazgos |
|---|---|---|---|
| 1 | Ocultar API keys | ❌ | S1 |
| 2 | Variables de entorno | ⚠️ | S4 (SECRET_KEY por defecto, sin uso real) |
| 3 | Keys en git | ❌ | S2, S3 |
| 4 | Proteger ruta admin | ❌ | A2 ✔vivo |
| 5 | Agregar auth | ❌ | A5, A6 ✔vivo |
| 6 | Permisos de usuario | ❌ | A1 ✔vivo, A3 ✔vivo |
| 7 | Sanitizar inputs | ❌ | E8, E9 |
| 8 | Protección XSS | ❌ | E6, E7 |
| 9 | Evitar SQL injection | ❌ | E1 ✔vivo |
| 10 | Reglas de la DB | ⚠️ | A8 |
| 11 | Rate limiting | ❌ | A7 ✔vivo |
| 12 | Límite de gasto | ❌ | A4 ✔vivo · ❓ tope en OpenAI |
| 13 | Asegurar subidas | ❌ | E4 ✔vivo |
| 14 | Protección CSRF | ❌ | E11 ✔vivo |
| 15 | Revisar CORS | ❌ | E10 ✔vivo |
| 16 | Habilitar HTTPS | ❓ | local; preguntar producción |
| 17 | Headers de seguridad | ❌ | S7 ✔vivo |
| 18 | Asegurar cookies | ❌ | E12 ✔vivo |
| 19 | Quitar modo debug | ❌ | S5 ✔vivo |
| 20 | Config de producción | ❌ | S6, S8 |
| X1–X6 | SSRF ❌ ✔vivo · Deserialización ❌ · Traversal ❌ · Lógica ✅ · CI/CD N/A · Monitoreo ❌ | | |

## Hallazgos (extracto)

#### E1 · SQL injection en `/buscar` — CRÍTICA — chequeo 9 — CONFIRMADO EN VIVO
- **Dónde**: `app/main.py:57` — `f"... LIKE '%{q}%'"`
- **Prueba**: `q=zzz%' OR 1=1 -- ` → 2 filas; `AND 1=2` → 0; `UNION SELECT 'INYECCION-OK',1` → marcador devuelto; sqlmap: *UNION query injectable* (sin extracción).
- **Arreglo**: `execute("SELECT nombre, precio FROM productos WHERE nombre LIKE ?", (f"%{q}%",))`

#### A3 · IDOR en `/pedidos/{id}` — CRÍTICA — chequeo 6 — CONFIRMADO EN VIVO
- **Prueba**: con la sesión de beto, `GET /pedidos/1` devolvió el pedido y la dirección de ana.
- **Arreglo**: `WHERE id = ? AND usuario = ?` con el id de la sesión; 404 si no es suyo.

#### S2 · `.env` en el historial de git — CRÍTICA — chequeo 3 — CONFIRMADO POR CÓDIGO
- **Dónde**: commit `inicio` agrega `.env` (`DATABASE_URL`, `STRIPE_SECRET`); `quitar .env` solo lo saca del árbol.
- **Nota**: gitleaks no lo detecta (valores sin formato conocido); lo encontró la revisión de archivos sensibles del historial.
- **Arreglo**: rotar ambas; opcional `git filter-repo --path .env --invert-paths`.

_(El reporte completo trae los ~30 hallazgos con evidencia y arreglo.)_

## Tratamiento: mejores implementaciones para este proyecto

| Prioridad | Mejora | Impacto | Esfuerzo | Plantilla |
|---|---|---|---|---|
| 1 | Rotar secretos y moverlos al gestor del hosting | crítico | 30 min | — |
| 2 | `endurecer(app)`: headers, CORS estricto, slowapi, errores genéricos, sin `/docs` | alto | 20 min | `plantillas/fastapi_seguridad.py` |
| 3 | argon2id con rehash al iniciar sesión + cookie `__Host-` | alto | 30 min | idem |
| 4 | Modelos con `extra="forbid"` y `max_length` | alto | 20 min | idem |
| 5 | Dockerfile slim no root + `.dockerignore` + DB sin `ports` | alto | 15 min | `plantillas/otros.md` |
| 6 | gitleaks en pre-commit + workflow de seguridad + Dependabot | alto | 15 min | `plantillas/` |
| 7 | Tests de autorización ("B no ve lo de A") por endpoint | medio | 1 h | — |

## Preguntas para ti

- ❓ 16: ¿Dónde se publica en producción? ¿Cloudflare en Full (strict) y redirección 301 a https?
- ❓ 12: ¿La cuenta de OpenAI tiene tope mensual y alertas?
- ❓ 20: ¿Hay respaldos probados de la base? ¿Cuál es la DB real, SQLite o Postgres?

## Lo que se revisó y se descartó

- `ORDER BY {columna}` en `/productos`: lista blanca. · MD5 en `/etag`: checksum de caché. ·
  `requests.get(config.CATALOGO_URL)`: URL del servidor. · Consultas con `?`: parametrizadas.

## Cómo se hizo

Escáneres: gitleaks 8.30.1, semgrep 1.184.0, pip-audit 2.10.1 (25 CVE en 4 paquetes) · Agentes: infra-secretos, acceso,
entradas, pentester, verificador (ajustó 6 severidades) · Pentest: sqlmap 1.10 `--risk 1` sin extracción, curl; cuentas
`pentest-*` y archivo `pentest-traversal.txt` creados y borrados · Límites: HTTPS y topes del proveedor no verificables en local.
