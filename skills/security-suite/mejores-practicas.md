# Mejores implementaciones (catálogo de la suite)

Plantillas por stack: FastAPI → `plantillas/fastapi_seguridad.py` · Next.js + Supabase + Stripe →
`plantillas/nextjs-supabase.md` · Express → `plantillas/express.md` · varios → `plantillas/otros.md`.

De aquí sale la sección "Tratamiento" del reporte. Recomienda **solo lo que aplica al stack detectado**, ordenado
por impacto/esfuerzo, y apunta a la plantilla lista cuando exista.

## Siempre (cualquier proyecto)

| Mejora | Impacto | Esfuerzo | Plantilla |
|---|---|---|---|
| gitleaks en pre-commit (secretos nunca entran a git) | alto | 5 min | `plantillas/otros.md` |
| Workflow de seguridad en CI (gitleaks + semgrep + auditoría de deps) | alto | 10 min | `plantillas/github-actions-seguridad.yml` |
| Dependabot (pip, npm, actions, docker) | alto | 5 min | `plantillas/otros.md` |
| Rotar todo secreto que haya tocado git y moverlo al gestor de secretos del hosting | crítico | 30 min | — |
| Monitor de uptime + alerta de errores | medio | 15 min | — |
| `security.txt` | bajo | 2 min | `plantillas/otros.md` |
| Respaldo automático de la DB **y prueba de restauración** | alto | 1 h | — |
| Copia del respaldo **fuera del servidor e inmutable** (R2/S3/B2 con Object Lock o credencial sin permiso de borrar) + 2FA en hosting, DB y almacenamiento (X12) | alto | 1 h | `plantillas/otros.md` |
| Logs de auth y admin enviados fuera del servidor, retención ≥ 90 días, alerta de logins fallidos y nuevo admin (X6) | alto | 30 min | — |

## FastAPI / Python

| Mejora | Chequeos | Plantilla |
|---|---|---|
| `Ajustes` con pydantic-settings sin defaults para secretos | 2, 19 | `plantillas/fastapi_seguridad.py` |
| `crear_app()` sin `/docs` en producción y `debug=False` | 19 | idem |
| argon2id (`argon2-cffi`) + rehash transparente al login de hashes viejos | 5 | idem |
| slowapi con IP real (`CF-Connecting-IP` solo detrás de tunnel) | 11 | idem |
| Cookie `__Host-` HttpOnly/Secure/SameSite=Lax | 18 | idem |
| Middleware de headers + CSP + HSTS | 17 | idem |
| CORS con lista explícita | 15 | idem |
| Manejador de errores genérico | 19 | idem |
| Dependencia `usuario_actual` + filtro por dueño en cada consulta (404 si no es suyo) | 6 | comentario en idem |
| Modelos con `extra="forbid"` y `max_length` | 7 | comentario en idem |
| Subidas: `uuid4()` como nombre, tamaño máx. leyendo por bloques, tipo real con Pillow (`Image.open().verify()` + re-guardar) | 13 | — |
| `yaml.safe_load`, nunca `pickle` con datos externos | X2 | — |
| Tests de autorización: por cada endpoint, "usuario B no ve lo de A" | 6 | — |

## Astro / front

- Nunca `set:html` / `innerHTML` con datos de usuario; si hace falta HTML, DOMPurify.
- Headers por `public/_headers` (Cloudflare) o middleware; CSP nativa de Astro si tu versión la trae (revisa la doc
  de tu versión: `security.csp`).
- `security.checkOrigin` activo en páginas on-demand (protección CSRF de formularios).
- Ninguna clave privada en variables `PUBLIC_*`; las llamadas con secretos van en endpoints del servidor.

## Cloudflare (si el dominio está ahí)

- SSL/TLS **Full (strict)**, Always Use HTTPS, HSTS, TLS mínimo 1.2.
- **Cloudflare Tunnel** en vez de abrir puertos; el origen no responde a internet directo.
- **Access** (Zero Trust) delante de `/admin`, paneles, Dokploy/Portainer, phpMyAdmin.
- Regla de **rate limiting** en `/login` y endpoints caros (el plan gratis trae una regla).
- **Turnstile** en formularios públicos, validado en el servidor (Siteverify).
- Bot Fight Mode; WAF managed rules si el plan lo permite.

## Docker / despliegue

- Imagen slim, usuario no root, `.dockerignore`, sin `--reload`, healthcheck.
- DB/Redis sin `ports:`; secretos por env/secrets del orquestador (Dokploy, Coolify, etc.).
- Logs sin tokens, contraseñas ni datos personales completos.

## Pagos y webhooks (X10, X4)

- Verificar la firma del webhook con el **cuerpo crudo** antes de tocar la base: FastAPI `await request.body()` +
  `stripe.Webhook.construct_event(cuerpo, firma, secreto)`; Express `express.raw()` + `stripe.webhooks.constructEvent`.
  Mercado Pago: HMAC-SHA256 de `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` con `hmac.compare_digest`.
- Tabla `eventos_webhook(id UNIQUE)`: insertar el ID del evento primero; si ya existe, responder 200 sin hacer nada.
- Cruzar monto, moneda y pedido con la base; el precio sale **siempre** del servidor (Stripe: `price` de catálogo, no
  `price_data` armado en el front).
- La página de éxito solo **muestra** el estado que ya escribió el webhook; nunca marca nada como pagado.
- Cupones: `UPDATE cupones SET usos = usos + 1 WHERE codigo = ? AND usos < max_usos` y revisar filas afectadas.

## Códigos cortos (OTP, recuperación, verificación) (11)

- `secrets.randbelow(10**6)` / `crypto.randomInt(0, 1e6)`; guardar el **hash** del código, no el código.
- Contador de intentos por código: al 5.º fallo se invalida; caducidad 10 min; un código vigente por cuenta.
- Respuesta idéntica exista o no la cuenta; rate limit por cuenta además de por IP.

## Chatbots y funciones con LLM (X11)

- System prompt sin secretos ni datos de clientes (suponer que se filtra).
- Herramientas: reciben el usuario **de la sesión** desde el servidor (nunca del modelo) y aplican el mismo filtro
  por dueño que la API; acciones que cambian datos o dinero piden confirmación del usuario en la UI.
- RAG: filtrar documentos por usuario/tenant en la consulta al índice, antes del modelo.
- Respuesta pintada como texto (`textContent`) o markdown sanitizado (DOMPurify) sin imágenes remotas.
- Endpoint con sesión, rate limit, `max_tokens` y tope diario por usuario.
- Prueba: `scripts/chatbot-inyeccion.py` en cada cambio del prompt o de las herramientas.

## APIs de pago (LLM, WhatsApp, SMS, correo)

- Tope de gasto + alerta en cada proveedor (revisar en su panel).
- Límite diario por usuario en la app, `max_tokens` fijo, endpoint nunca anónimo.
- Claves separadas por entorno y por proyecto, con el mínimo de permisos.
