# Hoja de respuestas del fixture

Lo que un diagnóstico correcto de `crear-fixture.sh` debe encontrar. Sirve para medir la suite (y comparar modelos).

## Fallas plantadas

| ID | Falla | Dónde | Chequeo | Severidad mínima |
|---|---|---|---|---|
| V01 | `.env` en el **historial** de git (DATABASE_URL, STRIPE_SECRET) → rotar | commit `inicio` | 3 | CRÍTICA |
| V02 | Clave privada de OpenAI en código del navegador | `frontend/src/config.js` | 1 | CRÍTICA |
| V03 | `SECRET_KEY` con valor por defecto `changeme` | `app/config.py` | 2 | ALTA |
| V04 | `/admin/usuarios` sin autenticación | `app/main.py` | 4 | CRÍTICA |
| V05 | IDOR en `/pedidos/{id}` | `app/main.py` | 6 | ALTA |
| V06 | Mass assignment: `rol` desde el body en `/registro` | `app/main.py` | 6/7 | CRÍTICA |
| V07 | SQL injection por f-string en `/buscar` | `app/main.py` | 9 | CRÍTICA |
| V08 | XSS almacenado con `| safe` (reseñas escritas por usuarios en `POST /resena/{pid}`) | `app/templates/resena.html` | 8 | ALTA |
| V09 | DOM XSS con `innerHTML` sobre `GET /api/resenas/{pid}` | `frontend/src/resenas.js` | 8 | ALTA |
| V10 | Subidas: `filename` del cliente (path traversal), sin tipo ni tamaño | `/subir` | 13 | CRÍTICA |
| V11 | CORS `*` con credenciales | `app/main.py` | 15 | ALTA |
| V12 | Cookie de sesión sin flags | `/login` | 18 | ALTA |
| V13 | GET que cambia estado (`/cuenta/borrar`) → CSRF | `app/main.py` | 14 | ALTA |
| V14 | `/debug` devuelve el entorno; `debug=True`; `/docs` público | `app/main.py`, `config.py` | 19 | CRÍTICA |
| V15 | `--reload`, root, sin `.dockerignore`, Postgres publicado con contraseña por defecto | `Dockerfile`, compose | 20 | ALTA |
| V16 | Sin rate limiting (login, registro, asistente) | — | 11 | ALTA |
| V17 | `/asistente` llama a OpenAI sin auth ni tope | `app/main.py` | 12 | ALTA |
| V18 | Contraseñas con MD5 | `/registro`, `/login` | 5 | ALTA |
| V19 | SSRF en `/vista-previa?url=` | `app/main.py` | X1 | ALTA |
| V20 | `yaml.load` y `pickle.loads` con datos del usuario | `/importar`, `/carrito` | X2 | CRÍTICA |
| V21 | Dependencias con CVE (jinja2, requests, pyyaml, fastapi…) | `requirements.txt` | 20 | ALTA |
| V22 | Sin headers de seguridad; `server: uvicorn` | — | 17 | MEDIA |
| V23 | HTTPS y topes de gasto como **preguntas** | — | 16, 12 | ❓ |
| V24 | JWT acepta `alg=none` | `leer_jwt`, `/api/yo` | 5 | CRÍTICA |
| V25 | Clave del JWT débil (`secret`) → se fabrican tokens de admin | `JWT_SECRETO` | 5, 2 | CRÍTICA |
| V26 | JWT sin `exp` | `/api/token` | 5 | MEDIA |
| V27 | IDOR en la API con token: `/api/pedidos/{id}` no revisa el dueño | `api_pedido` | 6 | ALTA |
| V28 | Condición de carrera: el canje lee, espera y escribe → 10 canjes con 100 puntos | `/api/canjear` | X4 | ALTA |
| V29 | Checkout: `confirmar` no revisa `pagado` → pedido sin pagar | `/api/checkout/*` | X4 | ALTA |
| V30 | Webhook de pago sin firma: cualquier POST marca un pedido como pagado | `/api/webhook/pago` | X10 | CRÍTICA |
| V31 | Código de recuperación de 6 dígitos con `random`, sin límite de intentos ni caducidad → robo de cuenta | `/recuperar/verificar` | 11 | CRÍTICA |
| V32 | Asistente: código interno `STAFF-90` en el system prompt y herramienta `ver_pedido` sin filtro por dueño | `/api/asistente` | X11 | CRÍTICA |
| V33 | Sin registro de auth/admin y sin respaldos fuera del servidor (como **preguntas**) | — | X6, X12 | ALTA / ❓ |

## Trampas (NO deben reportarse como falla)

| ID | Código | Por qué es seguro |
|---|---|---|
| T1 | `ORDER BY {columna}` en `/productos` | lista blanca |
| T2 | `hashlib.md5` en `/etag` | checksum de caché |
| T3 | `requests.get(f"{config.CATALOGO_URL}/lista")` | URL del servidor |
| T4 | `execute("... ?", (x,))` | parametrizada |
| T5 | `/api/admin/usuarios` | sí exige `rol == admin` del token (la falla es V24/V25, no la ruta) |
| T6 | `/api/webhook/envios` | verifica HMAC del cuerpo crudo con `hmac.compare_digest` |

## Fixture Next.js + Supabase (`crear-fixture-next.sh`, solo estático)

La app típica que genera una herramienta de IA. Patrones para el calificador en `esperado-next.json`.

| ID | Falla | Dónde | Chequeo | Severidad mínima |
|---|---|---|---|---|
| N01 | `NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY`: la service_role llega al navegador | `lib/supabase.ts`, `.env.local` | 1 | CRÍTICA |
| N02 | `.env.local` en el historial de git | commit `proyecto generado` | 3 | CRÍTICA |
| N03 | Tabla `pedidos` sin RLS | `supabase/migrations` | 10 | CRÍTICA |
| N04 | `mensajes`: `for all to authenticated using (true) with check (true)` | idem | 10/6 | ALTA |
| N05 | `reportes` "solo admin" decide con `user_metadata` (lo edita el usuario) | idem | 6 | CRÍTICA |
| N06 | `/admin` protegido solo con un `if` en el navegador | `app/admin/page.tsx` | 4 | CRÍTICA |
| N07 | Checkout cobra el `precio` que manda el cliente | `app/api/checkout/route.ts` | X4 | CRÍTICA |
| N08 | Webhook de Stripe sin `constructEvent` marca pedidos como pagados | `app/api/webhooks/stripe/route.ts` | X10 | CRÍTICA |
| N09 | `/api/pedidos/[id]` con service_role y sin filtro por dueño | `app/api/pedidos/[id]/route.ts` | 6 | CRÍTICA |
| N10 | OTP con `Math.random`, sin límite de intentos ni caducidad | `app/api/otp/*` | 11 | ALTA |
| N11 | Código interno `CUPON-STAFF-100` en el system prompt | `app/api/chat/route.ts` | X11 | ALTA |
| N12 | Respuesta del LLM con `dangerouslySetInnerHTML` | `components/Chat.tsx` | 8/X11 | ALTA |
| N13 | Open redirect con `?next=` | `app/api/salir/route.ts` | X3 | MEDIA |
| N14 | Subida con `file.name` y `file.type` del cliente a un bucket público, `upsert` | `app/api/subir/route.ts` | 13 | ALTA |
| N15 | `canjear_cupon`: lee y luego escribe (carrera) y `security definer` sin `search_path` | migración | X4/10 | ALTA |
| N16 | `next` 14.1.0 (bypass de middleware, CVE-2025-29927) y source maps en producción | `package.json`, `next.config.js` | 20/19 | ALTA |
| N17 | Sin headers de seguridad | `next.config.js` | 17 | MEDIA |
| N18 | Respaldos, logs y topes de gasto como **preguntas** | — | X12, X6, 12 | ❓ |

| ID | Trampa | Por qué es seguro |
|---|---|---|
| NT1 | `profiles` | RLS con `auth.uid() = id` (que el usuario pueda editar su columna `rol` sí es un hallazgo válido, BAJA) |
| NT2 | `productos` con `using (true)` para select | catálogo público a propósito, sin políticas de escritura |
| NT3 | `app/api/webhooks/lemon` | HMAC del cuerpo crudo con `timingSafeEqual` |
| NT4 | anon key en el bundle | es pública por diseño; lo que protege es la RLS |

Herramientas sin IA (2026-11-26): `supabase-rls.py` encuentra N01, N03, N04, N05 y N15 (MEDIA); con `--publicas productos`
no marca NT2. Las reglas de semgrep de la suite encuentran N01, N07, N08, N09, N10, N11, N12 y N13, y no marcan NT3.

## Puntuación

- **Recall** = V01–V22 y V24–V32 encontradas / 31 (V23 y V33 suman si aparecen como preguntas). V24–V29 requieren el pentest
  con las herramientas (`jwt-revisar.py`, `matriz-permisos.py`, `carrera.py`, `flujo.py`) y 2 cuentas: ana y beto.
- **Confirmadas en vivo** (modo completo): V04, V05, V06, V07, V11, V12, V13, V14, V16, V30, V31 deberían salir CONFIRMADAS
  (V32 necesita una clave real de OpenAI: sin ella queda confirmada por código).
- **Precisión**: cada trampa reportada como falla resta 1.
- **Higiene**: ningún secreto completo en el reporte; el fixture no se modificó (`git status` limpio salvo `tienda.db`).

## Línea base (sin la skill, 2026-11-09)

Un agente sin skill encontró ~20/22, no cayó en trampas, pero **no vio V01** (dijo "el .env está en .gitignore")
y no hizo preguntas (V23). gitleaks solo tampoco detecta V01.

## Resultados registrados

| Fecha | Modelo | Recall | Trampas reportadas | Confirmadas en vivo | Notas |
|---|---|---|---|---|---|
| 2026-11-09 | sin skill (línea base) | ~20/22 | 0 | — | no vio V01 ni hizo preguntas |
| 2026-11-09 | Opus 5.5 + security-suite v1 | 22/22 + preguntas | 0 | 14/14 probadas | verificador ajustó 6 severidades; XSS bajó a MEDIA porque el fixture no tenía escritura de reseñas (corregido después) |

| 2026-11-27 | Opus 5.5 + security-suite v1.2, modo completo | 31/31 + 2/2 preguntas | 0 | 20 de 31 (el resto, por código) | 618k tokens nuevos + 7,8M de caché en los 5 subagentes (sin contar la sesión principal); el verificador no encontró falsos positivos |
| 2026-11-27 | Opus 5.5 + security-suite v1.2, `rapido-ia` (fixture Next.js) | 17/17 + 1/1 pregunta | 0 | — (solo estático) | 75k nuevos + 979k de caché, un solo agente; encontró además que `profiles` deja editar la columna `rol` (BAJA, válido) |

Notas de la corrida del 2026-11-27: el calificador se corrigió durante la corrida (contaba como trampas los descartes y
sumaba la caché al total). `matriz-permisos.py` borró las 3 cuentas demo al ejecutar `GET /cuenta/borrar`: corregido y con
prueba. Sin una corrida de v1.1 con la misma medición, todavía no hay comparación de ahorro antes/después.

### Herramientas de nivel 2–3 (2026-11-10, fixture en :8766)

| Herramienta | Encontró | Falsos positivos |
|---|---|---|
| `jwt-revisar.py` | V24, V25 (clave `se…`), V26 | 0 (control: token HS256 con clave de 48 bytes y `exp` → ✅) |
| `matriz-permisos.py` | V27 (ana↔beto, "recibe exactamente lo mismo que el dueño") | 0 (T5: admin 403 para clientes) |
| `carrera.py` | V28 (10 éxitos de 10) | — |
| `flujo.py` (+ `grabar-flujo.py` con Playwright) | V29 ("Saltar pagar" termina con éxito) | 0 (saltar carrito, repetir y solo-último → rechazados) |
| `fuzz-api.sh` | 500 con traceback en `/vista-previa` (V14/V19), parámetros que aceptan cualquier cosa | — |

### Herramientas de v1.1 (2026-11-26, fixture en :8799)

| Herramienta | Encontró | Falsos positivos |
|---|---|---|
| `webhook-falso.py` | V30 (sin firma y con firma Stripe falsa → 200; el pedido 2 quedó `pagado = 1`) | 0 (T6 → 401 en las dos pruebas) |
| ≤ 10 códigos erróneos con `curl` | V31 (10 × 400 sin bloqueo; el código correcto siguió sirviendo) | — |
| reglas de semgrep de la suite | V30 (`webhook-sin-firma`), V31 (`codigo-con-random`) | 0 (T6 no marcado) |
