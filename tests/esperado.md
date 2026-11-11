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

## Trampas (NO deben reportarse como falla)

| ID | Código | Por qué es seguro |
|---|---|---|
| T1 | `ORDER BY {columna}` en `/productos` | lista blanca |
| T2 | `hashlib.md5` en `/etag` | checksum de caché |
| T3 | `requests.get(f"{config.CATALOGO_URL}/lista")` | URL del servidor |
| T4 | `execute("... ?", (x,))` | parametrizada |
| T5 | `/api/admin/usuarios` | sí exige `rol == admin` del token (la falla es V24/V25, no la ruta) |

## Puntuación

- **Recall** = V01–V22 y V24–V29 encontradas / 28 (V23 suma si aparece como pregunta). V24–V29 requieren el pentest
  con las herramientas (`jwt-revisar.py`, `matriz-permisos.py`, `carrera.py`, `flujo.py`) y 2 cuentas: ana y beto.
- **Confirmadas en vivo** (modo completo): V04, V05, V06, V07, V11, V12, V13, V14, V16 deberían salir CONFIRMADAS.
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

### Herramientas de nivel 2–3 (2026-11-10, fixture en :8766)

| Herramienta | Encontró | Falsos positivos |
|---|---|---|
| `jwt-revisar.py` | V24, V25 (clave `se…`), V26 | 0 (control: token HS256 con clave de 48 bytes y `exp` → ✅) |
| `matriz-permisos.py` | V27 (ana↔beto, "recibe exactamente lo mismo que el dueño") | 0 (T5: admin 403 para clientes) |
| `carrera.py` | V28 (10 éxitos de 10) | — |
| `flujo.py` (+ `grabar-flujo.py` con Playwright) | V29 ("Saltar pagar" termina con éxito) | 0 (saltar carrito, repetir y solo-último → rechazados) |
| `fuzz-api.sh` | 500 con traceback en `/vista-previa` (V14/V19), parámetros que aceptan cualquier cosa | — |
