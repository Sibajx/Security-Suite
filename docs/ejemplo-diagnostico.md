# Diagnóstico de seguridad — tienda-demo (fixture de pruebas)

> Ejemplo real de salida de la suite v1.2 en modo `completo` sobre `tests/crear-fixture.sh` (app con fallas plantadas
> y datos falsos), corrida el 2026-11-27. Calificación con `tests/calificar.py`: 31/31 fallas, 0 trampas, 0 secretos.
> Para un ejemplo del modo `rapido-ia` ver [`ejemplo-rapido-ia.md`](ejemplo-rapido-ia.md).

**Fecha:** 2026-11-27 · **Commit:** `af973b6886` · **Modo:** completo · **Objetivo en vivo:** http://127.0.0.1:8765 (local, nivel 3, autorizado por el usuario: sí)

## Veredicto

🔴 **NO DESPLEGAR**

**0/19 chequeos pasan** (de los que aplican; 16 HTTPS queda ❓) · CRÍTICAS: 15 · ALTAS: 16 · MEDIAS: 4 · confirmadas en vivo: 20

Cualquier persona sin cuenta puede hoy leer todas las claves del servidor (`/debug`), volverse administradora (registro con
`rol`, JWT con `alg=none` o firmado con `secret`), leer la base entera (inyección SQL en `/buscar`), escribir archivos
fuera de la carpeta de subidas y marcar pedidos como pagados sin pagar (webhook sin firma). Con un código de recuperación
de 6 dígitos sin límite de intentos se toma cualquier cuenta. Hay claves de OpenAI, Stripe y la base en git: hay que rotarlas.

## Lo urgente (hacer hoy)

1. **Rotar** la clave de OpenAI, `STRIPE_SECRET` y la contraseña de `DATABASE_URL` — CRÍTICA — `frontend/src/config.js:2`, `.env` en el commit `f563a59` — confirmado por código. Borrarlas no basta: siguen en git.
2. **Quitar `/debug` y apagar el modo debug** — CRÍTICA — `app/main.py:308`, `app/config.py:4` — confirmado en vivo.
3. **Arreglar la autenticación**: JWT con PyJWT (`algorithms=["HS256"]`, secreto de entorno ≥ 32 bytes, `exp`), registro sin `rol`, auth + rol en `/admin/usuarios`, filtro por dueño en `/pedidos` y `/api/pedidos` — CRÍTICA — `app/main.py:23-183` — confirmado en vivo.
4. **Parametrizar `/buscar`, quitar `pickle.loads` y `yaml.load`, nombre de archivo del servidor en `/subir`** — CRÍTICA — `app/main.py:57,84-105` — confirmado en vivo.
5. **Verificar la firma del webhook de pago y limitar el código de recuperación** (5 intentos, 10 min, `secrets`) — CRÍTICA — `app/main.py:239,267-280` — confirmado en vivo.

## Los 20 chequeos

| # | Chequeo | Estado | Hallazgos |
|---|---|---|---|
| 1 | Ocultar API keys | ❌ | S1 (❓ ¿qué frontend publica `frontend/src`?) |
| 2 | Variables de entorno | ❌ | S4 |
| 3 | Keys en git | ❌ | S1, S2 |
| 4 | Proteger ruta admin | ❌ | A1 ✔vivo |
| 5 | Agregar auth | ❌ | A3 ✔vivo, A4, A11, P1 ✔vivo |
| 6 | Permisos de usuario | ❌ | A2 ✔vivo, A9 ✔vivo |
| 7 | Sanitizar inputs | ❌ | A2, E14 |
| 8 | Protección XSS | ❌ | E6 ✔vivo, E7 |
| 9 | Evitar SQL injection | ❌ | E1 ✔vivo |
| 10 | Reglas de la DB | ⚠️ | sin acceso directo del cliente; Postgres del compose con superusuario (S6) |
| 11 | Rate limiting | ❌ | A8 ✔vivo, A5 ✔vivo |
| 12 | Límite de gasto | ❌ | E13 ✔vivo · ❓ tope en OpenAI |
| 13 | Asegurar subidas | ❌ | E4 ✔vivo |
| 14 | Protección CSRF | ❌ | E10 ✔vivo |
| 15 | Revisar CORS | ❌ | E9 ✔vivo |
| 16 | Habilitar HTTPS | ❓ | local; preguntar producción |
| 17 | Headers de seguridad | ❌ | S9 ✔vivo |
| 18 | Asegurar cookies | ❌ | E11 ✔vivo |
| 19 | Quitar modo debug | ❌ | S3 ✔vivo, S7 ✔vivo |
| 20 | Config de producción | ❌ | S5, S6, S8 |
| X1–X12 | SSRF ❌ (E8 ✔vivo) · Ejecución ❌ (E2, E3) · Traversal ❌ (E4) · Lógica ❌ (A6, A7 ✔vivo) · CI/CD N/A · Registro ❌ (S10) · Superficie ❓ · Correo/DNS ❓ · Access N/A · Webhooks de pago ❌ (A4b ✔vivo) · LLM ❌ (E12, E13) · Respaldos ❌ (S11) | | |

## Hallazgos

Unidos los duplicados de los 3 auditores; el verificador no encontró falsos positivos (E7 bajó a MEDIA, E14 a MEDIA).

### CRÍTICAS

#### S1 · Clave de OpenAI en el código del frontend y en git — CRÍTICA — chequeos 1, 3 — CONFIRMADO POR CÓDIGO
- **Dónde**: `frontend/src/config.js:2` (`OPENAI_API_KEY = "sk-p…"`), commit `af973b6`.
- **Arreglo**: rotar la clave; el front llama a la API propia, nunca a OpenAI.

#### S2 · `.env` en el historial de git (DATABASE_URL, STRIPE_SECRET) — CRÍTICA — chequeo 3 — CONFIRMADO POR CÓDIGO
- **Dónde**: commit `f563a59` lo agrega, `78bd92f` solo lo saca del árbol. gitleaks lo marca; la revisión de archivos sensibles del historial lista las variables.
- **Arreglo**: rotar ambas; opcional `git filter-repo --path .env --invert-paths`.

#### S3 · `/debug` devuelve todas las variables de entorno — CRÍTICA — chequeo 19 — CONFIRMADO EN VIVO
- **Prueba**: `GET /debug` sin sesión → 200 con 5 variables, incluida `OPENAI_API_KEY` (solo se listaron nombres). Repro `repro/S3.sh`.

#### A3 · JWT acepta `alg=none`, clave débil `secret` (`JWT_SECRETO`) y sin `exp` — CRÍTICA — chequeos 5, 2 — CONFIRMADO EN VIVO
- **Dónde**: `app/main.py:133,151-152,170`.
- **Prueba**: token `alg=none` con `rol: admin` → `/api/admin/usuarios` 200; token HS256 firmado con `secr…` → 200 (`jwt.md`). Además `SECRET_KEY` con defecto `changeme` (`app/config.py:3`, sin uso).
- **Arreglo**: `jwt.decode(tok, SECRETO, algorithms=["HS256"])`, secreto de entorno de 48 bytes, `exp` de 15–60 min, rol leído de la base.

#### A1 · `/admin/usuarios` sin autenticación — CRÍTICA — chequeo 4 — CONFIRMADO EN VIVO
- **Prueba**: `GET /admin/usuarios` sin cookie → 200 con la lista de usuarios (`matriz.md`).

#### A2 · Mass assignment: el registro acepta `rol` → cuenta admin — CRÍTICA — chequeos 6, 7 — CONFIRMADO EN VIVO
- **Prueba**: cuenta `pentest-*` registrada con `"rol":"admin"` → token con rol admin → `/api/admin/usuarios` 200 (control cliente: 403).
- **Arreglo**: modelo de registro con `extra="forbid"` y sin `rol`; `INSERT` con `'cliente'` fijo.

#### A9 · IDOR en `/pedidos/{id}` y `/api/pedidos/{pid}` (y la herramienta del asistente) — CRÍTICA — chequeo 6 — CONFIRMADO EN VIVO
- **Prueba**: beto lee el pedido 1 de ana («Calle Ana 1») por cookie y por token (`matriz.md`).
- **Arreglo**: `WHERE id = ? AND usuario = ?` con el id de la sesión; 404 si no es suyo.

#### E1 · SQL injection en `/buscar` — CRÍTICA — chequeo 9 — CONFIRMADO EN VIVO
- **Dónde**: `app/main.py:57` (`f"... LIKE '%{q}%'"`).
- **Prueba**: UNION devolvió la versión de SQLite; sqlmap `--risk 1`: boolean, error y time-based, sin extracción.

#### E2 / E3 · `pickle.loads` en `/carrito` y `yaml.load(Loader=yaml.Loader)` en `/importar` — CRÍTICA — chequeo X2 — CONFIRMADO (no explotado a propósito)
- **Prueba**: aceptan un pickle benigno y un tag `!!python/tuple`; no se ejecutaron payloads de código (reglas).
- **Arreglo**: JSON validado con Pydantic; `yaml.safe_load`.

#### E4 · Subida con el `filename` del cliente: path traversal — CRÍTICA — chequeos 13, X3 — CONFIRMADO EN VIVO
- **Prueba**: un `.txt` con filename `../../pentest-traversal.txt` se escribió en la raíz del proyecto (borrado). `/subir` es anónimo; con `--reload` permite pisar código.

#### E6 · XSS almacenado en reseñas con `|safe` — CRÍTICA (sube: cookie sin HttpOnly y sin CSP) — chequeo 8 — CONFIRMADO EN VIVO
- **Dónde**: `app/templates/resena.html:3`. **Prueba**: un marcador inofensivo salió sin escapar (reseñas borradas).

#### A4b · Webhook de pago sin firma — CRÍTICA — chequeo X10 — CONFIRMADO EN VIVO
- **Dónde**: `POST /api/webhook/pago` (`app/main.py:239-245`). **Prueba**: `webhook-falso.py` sin firma y con firma Stripe falsa → 200 y `pagado=1` en el pedido de prueba 9001 (borrado).
- **Arreglo**: `stripe.Webhook.construct_event` con el cuerpo crudo, tabla de eventos procesados, cruzar monto con la base.

#### A5 · Código de recuperación de 6 dígitos con `random`, sin límite de intentos ni caducidad — CRÍTICA — chequeo 11 — CONFIRMADO EN VIVO
- **Dónde**: `/recuperar` y `/recuperar/verificar` (`app/main.py:267-280`). **Prueba**: 10 códigos erróneos → 10 × 400 sin bloqueo; el correcto siguió sirviendo.
- **Arreglo**: `secrets.randbelow`, hash del código, 5 intentos, 10 min, `compare_digest`.

#### E12 · Asistente: código interno en el system prompt y herramienta `ver_pedido` sin filtro por dueño — CRÍTICA — chequeo X11 — CONFIRMADO POR CÓDIGO
- **Dónde**: `app/main.py:283-299` (`STAFF-90` en el prompt; la herramienta busca cualquier `pedido_id`). Sin clave real de LLM no se explotó en vivo; `/api/asistente` sí exige JWT (pero se forja con A3).

### ALTAS

- **S5** · Docker: sin `.dockerignore` (mete `.env`, `.git` y `tienda.db`), root, `python:3.12` completo, `--reload` — chequeos 3, 19, 20.
- **S6** · `docker-compose.yml` publica Postgres `5432:5432` con `POSTGRES_PASSWORD: postgres` — chequeos 2, 20.
- **S7** · `debug=True` con tracebacks al cliente; `/docs`, `/redoc`, `/openapi.json` públicos — chequeo 19 — ✔vivo (traceback en `/importar`, ffuf).
- **S8** · 13 CVE únicas (pip-audit lista 25 entradas): jinja2 2.11.2 → 3.1.6, requests 2.19.0 → 2.33.0, pyyaml 5.3 → 5.4+, fastapi 0.95.0 → 0.109.1; sin lockfile — chequeo 20.
- **S10** · Sin ningún registro de seguridad; el código de recuperación se imprime en los logs (`app/main.py:270`) — chequeo X6.
- **S11** · SQLite dentro del contenedor, sin volumen ni respaldo — chequeo X12.
- **A4** · Contraseñas con MD5 sin sal (`app/main.py:36,44,167,277`) — chequeo 5.
- **A6** · Checkout: `confirmar` no revisa `pagado` → pedido sin pagar — chequeo X4 — ✔vivo (`flujo.py`, saltar «pagar»).
- **A7** · Condición de carrera en `/api/canjear`: 10 canjes simultáneos con 100 puntos → 10 éxitos — chequeo X4 — ✔vivo (`carrera.py`).
- **A8** · Sin rate limit: 20 logins erróneos, ningún 429 — chequeo 11 — ✔vivo.
- **E8** · SSRF en `/vista-previa?url=` — chequeo X1 — ✔vivo (solo hacia el propio host).
- **E9** · CORS refleja cualquier `Origin` con `allow-credentials: true` — chequeo 15 — ✔vivo.
- **E10** · CSRF: `GET /cuenta/borrar` borra la cuenta — chequeo 14 — ✔vivo (cuenta desechable).
- **E11** · Cookie de sesión sin `HttpOnly` ni `Secure` — chequeo 18 — ✔vivo.
- **E13** · `/asistente` anónimo, sin rate limit y con `max_tokens=4000` — chequeos 12, X11 — ✔vivo (llega al proveedor sin auth).
- **P1** · El JWT de una cuenta borrada sigue autenticando (sin `exp` ni revocación) — chequeo 5 — ✔vivo.

### MEDIAS

- **S9** · Sin headers de seguridad (CSP, HSTS, nosniff, Referrer-Policy, Permissions-Policy, frame-ancestors) — chequeo 17.
- **E7** · `innerHTML` con reseñas en `frontend/src/resenas.js:2` (hoy nadie llama a `pintar`) — chequeo 8.
- **E14** · Validación débil: sin `max_length`, sin `EmailStr`, contraseña vacía aceptada en `/recuperar/verificar` — chequeo 7.
- **A11** · Sesión por cookie sin expiración ni logout; cambiar la contraseña no la invalida — chequeo 5.

## Tratamiento: mejores implementaciones para este proyecto

| Prioridad | Mejora | Impacto | Esfuerzo | Plantilla |
|---|---|---|---|---|
| 1 | Rotar secretos y moverlos al gestor del hosting | crítico | 30 min | — |
| 2 | `endurecer(app)`: headers, CORS estricto, slowapi, errores genéricos, sin `/docs` ni `/debug` | alto | 20 min | `plantillas/fastapi_seguridad.py` |
| 3 | PyJWT + argon2id con rehash + cookie `__Host-` + modelos `extra="forbid"` | alto | 1 h | idem |
| 4 | Webhook firmado e idempotente; código de recuperación con límite | alto | 1 h | `mejores-practicas.md` → Pagos y Códigos cortos |
| 5 | Dockerfile slim no root + `.dockerignore` + DB sin `ports` + volumen y respaldo inmutable | alto | 1 h | `plantillas/otros.md` |
| 6 | gitleaks en pre-commit + workflow de seguridad + Dependabot | alto | 15 min | `plantillas/` |
| 7 | Tests de autorización ("B no ve lo de A") por endpoint | medio | 1 h | — |

## Preguntas para ti

- ❓ 16: ¿Dónde se publica en producción y quién termina TLS? ¿Cloudflare en Full (strict) con 301 a https?
- ❓ 12: ¿La cuenta de OpenAI tiene tope mensual y alertas?
- ❓ 1: ¿Qué frontend publica `frontend/src` (y usa `pintar`)?
- ❓ X6: ¿Hay logs o monitor de uptime fuera del código? ¿Con qué retención y alertas?
- ❓ X12: ¿Hay algún respaldo de la base? ¿Fuera del servidor, inmutable, y cuándo se probó restaurarlo?
- ❓ 2: ¿`DATABASE_URL` (Postgres) es una base real en uso?

## Lo que se revisó y se descartó

- `ORDER BY {columna}` en `/productos`: lista blanca — correcto. · `hashlib.md5` en `/etag`: checksum de caché. ·
  `requests.get(config.CATALOGO_URL)`: URL del servidor. · Consultas con `?`: parametrizadas. ·
  `/api/admin/usuarios`: la verificación de rol es correcta (la falla es el token, A3). ·
  `/api/webhook/envios`: verifica HMAC del cuerpo crudo con `compare_digest` — correcto.

## Cómo se hizo

Escáneres: gitleaks 8.21.2, semgrep 1.187.0 (solo reglas de la suite: sin red para las públicas), pip-audit 2.10.1 ·
Agentes: infra-secretos, acceso, entradas, pentester, verificador · Pentest: sqlmap 1.10 `--risk 1` sin extracción,
ffuf 2.1, `jwt-revisar.py`, `matriz-permisos.py`, `carrera.py`, `flujo.py`, `webhook-falso.py`, curl; nuclei no disponible.
Lo que se creó: 11 cuentas `pentest-*`, 2 reseñas marcador, el pedido 9001 y `pentest-traversal.txt`: todo borrado.
**Incidente**: `matriz-permisos.py` ejecutó `GET /cuenta/borrar` con las sesiones de admin, ana y beto y borró esas 3
cuentas demo (la ruta estaba marcada `escritura_ok: false`, pero la herramienta solo frenaba métodos de escritura).
Se restauraron con `init_db.py` y la herramienta ya está corregida. Límites: HTTPS y topes del proveedor no verificables
en local; el asistente no se probó con un LLM real.
