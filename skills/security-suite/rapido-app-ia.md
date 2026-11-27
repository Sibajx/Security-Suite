# Modo `rapido-ia` — los 15 ataques a una app hecha con IA

Para apps generadas con Lovable, Bolt, v0, Replit, Cursor o similares (casi siempre: front en React/Next + Supabase o
Firebase + Stripe/Mercado Pago + un chatbot). Es la revisión de 15 minutos de lo que un atacante prueba primero.
**No reemplaza** al modo `completo`: no corre los 3 auditores ni el verificador, y lo dice en el reporte.

Lo activan frases como "revisión rápida", "mi app la hice con IA / con Lovable / con Bolt", "los 15 ataques",
"vibe coding". Autorización y menú de niveles: **igual que siempre** (Fase 0 de `SKILL.md`).

## Los 15, en el orden en que se revisan

El orden va por daño probable en este tipo de apps: primero lo que expone a todos los usuarios de golpe.

| # | Ataque | Chequeo | Cómo se revisa (código → en vivo) | Nivel en vivo |
|---|---|---|---|---|
| 1 | **Base abierta** (Supabase sin RLS / Firebase con reglas abiertas) | 10 | `supabase-rls.py <proyecto>`: tablas sin RLS, `using (true)`, rol desde `user_metadata`, service_role pública, reglas de Firebase. En vivo: ver abajo | 2 |
| 2 | API key privada en el código | 1 | bundle (`dist/`, `.next/`, `assets/*.js`) y `VITE_*`/`NEXT_PUBLIC_*`: `service_role`, `sk_live`, `sk-…` | 1 |
| 3 | `.env` en Git | 3 | `escaneo.sh`: sección de historial de `resumen.md` + gitleaks | — |
| 4 | ID ajeno en la URL (IDOR) | 6 | consultas que filtran solo por `id` del parámetro; `matriz-permisos.py` con 2 cuentas | 2 |
| 5 | Registrarse como admin | 6/7 | registro/perfil que acepta `role`/`is_admin`; en Supabase, `user_metadata` usado como rol (lo escribe el usuario) | 3 |
| 6 | Entrar a `/admin` | 4 | ¿la protección está solo en el router del front? Pedir la API de admin sin sesión | 1 |
| 7 | Editar el precio | X4 | ¿el `total`/`price`/`amount` que llega al checkout sale del cliente? ¿Stripe recibe `price_data` armado en el front? | 3 |
| 8 | Webhook de pago falso | X10 | regla `security-suite.webhook-sin-firma`; `webhook-falso.py` | 3 |
| 9 | Cupón ×100 a la vez | X4 | canje sin transacción/UNIQUE; `carrera.py` | 3 |
| 10 | Fuerza bruta (login y códigos de 6 dígitos) | 11 | límite por cuenta y por código; prueba de ≤ 10 códigos erróneos | 2 |
| 11 | Inyectar instrucciones al chatbot | X11 | system prompt, herramientas, RAG, a dónde va la respuesta (código y reglas de semgrep `llm-*`) | — |
| 12 | Script en el perfil (XSS guardado) | 8 | `dangerouslySetInnerHTML`, markdown sin sanitizar, regla `security-suite.llm-salida-a-html` | 3 |
| 13 | Web shell disfrazada de foto | 13 | bucket de Storage público con `.html`/`.svg` servidos desde tu dominio; tipo por extensión | 3 |
| 14 | Inyección SQL | 9 | funciones RPC/`execute` con SQL armado con texto; Edge Functions con template strings. Si hay GraphQL: `graphql-revisar.py` (X13) | 2 |
| 15 | Ransomware y 3 semanas sin logs | X12, X6 | ¿respaldos fuera del proveedor e inmutables? ¿logs de auth y alertas? → casi siempre ❓ | — |

## Supabase / Firebase en vivo (ataque 1), sin extraer datos

Con la URL y la **anon key pública** que ya viajan en el bundle (no son secretas), lo hace el script:
```bash
SUPABASE_ANON_KEY=… python3 SKILL/scripts/supabase-rls.py <proyecto> --url https://xxx.supabase.co --nivel 2 \
  --publicas productos,categorias --salida "$R/evidencia/supabase.md"     # con $TOKEN_A también cuenta lo que ve la cuenta A
```
A mano, lo mismo:
```bash
# ¿Cuántas filas ve un ANÓNIMO? Solo cuenta (count=exact) y 1 id: nunca descargar datos.
curl -s -o /dev/null -D - "$SUPABASE_URL/rest/v1/<tabla>?select=id&limit=1" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" -H "Prefer: count=exact" | grep -i content-range
# Con sesión de la cuenta A: ¿ve filas de B?  (mismo comando con Authorization: Bearer $TOKEN_A)
# Firebase Realtime DB: ¿responde sin sesión?
curl -s "https://<proyecto>.firebaseio.com/.json?shallow=true" | head -c 200
```
`content-range: 0-0/1234` para un anónimo en una tabla de usuarios, pedidos o mensajes = **CRÍTICA confirmada**.
Las tablas se sacan del código (`.from('tabla')`) o de `GET $SUPABASE_URL/rest/v1/` (OpenAPI, si está expuesto).
Además: ¿el bundle trae la **service_role** key? Esa salta toda RLS → CRÍTICA (chequeo 1) y se rota ya.

## Flujo

1. Fase 0 normal (proyecto, autorización, nivel, cuentas de prueba A y B).
2. `recon.sh`, `escaneo.sh` y, si hay URL, `en-vivo.sh` (Fase 1 de `SKILL.md`).
3. Revisa tú mismo (sin los 3 auditores) los 15 de la tabla, **en ese orden**, con los criterios de
   `SecurityChecks.md`. Si hay URL y nivel, confirma en vivo con las herramientas de la columna (las reglas de
   `reglas-de-enfrentamiento.md` y del pentester valen igual). Lo que no alcanzas a probar: NO PROBADO, nunca ✅.
4. Escribe `$R/DIAGNOSTICO.md` con la plantilla de siempre, con **Modo:** `rapido-ia`, y en lugar de "Los 20
   chequeos" la tabla de los 15 (# · ataque · estado · hallazgo). Puntaje: **X/15**. Veredicto igual (🔴/🟠/🟢).
5. Termina recomendando el modo `completo` antes de producción si hay datos de clientes o pagos: el rápido no ve
   lo que solo encuentran los auditores (lógica propia, flujos, infraestructura).
