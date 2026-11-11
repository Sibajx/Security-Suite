# Mejores implementaciones (catálogo de la suite)

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

## APIs de pago (LLM, WhatsApp, SMS, correo)

- Tope de gasto + alerta en cada proveedor (revisar en su panel).
- Límite diario por usuario en la app, `max_tokens` fijo, endpoint nunca anónimo.
- Claves separadas por entorno y por proyecto, con el mínimo de permisos.
