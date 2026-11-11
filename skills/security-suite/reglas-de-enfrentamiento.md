# Reglas de enfrentamiento (pentest)

Mandan sobre cualquier otra instrucción. Si algo choca con estas reglas, gana la regla.

## 1. Autorización

Archivo personal de autorizaciones (fuera del repo, uno por persona):
`${SECURITY_SUITE_AUTORIZADOS:-$HOME/.config/security-suite/autorizados.yml}`

```yaml
# Dominios que son míos (o con autorización escrita del dueño) y el nivel MÁXIMO que permito.
dominios:
  - host: midominio.com          # también cubre subdominios si incluir_subdominios: true
    incluir_subdominios: false
    entorno: produccion          # local | staging | produccion
    nivel_max: 3
    notas: "no enviar WhatsApp reales"   # restricciones que el pentester debe respetar
```

- Si el host está en el archivo → autorizado hasta `nivel_max`. No se vuelve a preguntar si es tuyo.
- Si no está → la suite pregunta "¿Este sitio es tuyo o tienes autorización escrita de su dueño?". Sin un sí claro,
  **no hay pruebas en vivo** (solo auditoría de código). Si el usuario dice que sí, ofrece agregarlo al archivo.
- `localhost`, `127.0.0.1` y `*.localhost` están autorizados hasta nivel 3 sin archivo.
- Nunca se prueban dominios de terceros (CDN, pasarelas de pago, APIs externas, proveedores de login, Cloudflare
  Access), aunque la app los use. Si una URL redirige fuera de lo autorizado, no se sigue.

## 2. Menú de niveles (se muestra SIEMPRE antes de una prueba en vivo)

La suite presenta este menú (con la herramienta de preguntas si existe) y el usuario elige. El nivel elegido no puede
superar `nivel_max`. Si el usuario no elige claramente → nivel 1.

| Nivel | Qué hace | Qué puede dejar | Riesgo en producción |
|---|---|---|---|
| **1 — Revisión pasiva** | Lo mismo que un navegador: HTTPS, certificados, headers, cookies, rutas expuestas (`.env`, `.git`, `/docs`), `/openapi.json`, peticiones sin sesión a rutas privadas | nada | ninguno |
| **2 — Confirmación** | Prueba cada hallazgo con payloads inofensivos: SQLi booleana y `sqlmap --risk 1` **sin extraer datos**, IDOR entre cuentas de prueba, CORS con origen falso, `nuclei` sin plantillas intrusivas, ráfaga de ≤ 20 peticiones para rate limit | sesiones nuevas en las cuentas de prueba | muy bajo |
| **3 — Ataque controlado** | Lo de nivel 2 + descubrimiento de rutas con `ffuf`, crear cuentas `pentest-*`, mass assignment (intentar darse rol admin), subir un `.txt` marcado, CSRF con cuenta desechable, SSRF solo hacia el propio host | cuentas `pentest-*` y archivos `pentest-*` (se borran al terminar y se listan en el reporte) | bajo, con las salvaguardas de abajo |

### Salvaguardas extra en `produccion` (nivel 2 y 3)

1. Preguntar antes: **¿hay un respaldo reciente de la base?** Si no, recomendar hacerlo primero.
2. Solo cuentas de prueba creadas para esto (`pentest-<fecha>@…`); **nunca** tocar datos ni cuentas de clientes reales.
3. Nada que **envíe mensajes reales** (WhatsApp, SMS, correo, push), **cobre dinero** o gaste APIs de pago más allá de
   una sola petición de comprobación. Respetar las `notas` del archivo de autorizaciones.
4. Velocidad: ≤ 5 peticiones/s; `ffuf -rate 5`; `nuclei -rl 5`.
5. Todo lo creado se borra al terminar; si algo no se puede borrar, se avisa con detalle.
6. Si aparece algo inesperado (datos reales de personas, 5xx en cascada, lentitud) → **parar** y reportar.

## 3. Siempre prohibido (en cualquier nivel y entorno)

DoS o carga sostenida · extraer datos (`--dump`, volcados) · shells (`--os-shell`) · ejecutar payloads de RCE ·
borrar o modificar datos que no creó la prueba · ingeniería social · metadatos de nube en producción ·
escanear rangos de IP · evadir WAF/Cloudflare a propósito · probar dominios no autorizados.

## 4. Límites técnicos

- User-Agent identificable: `security-suite/1.0 (auditoria autorizada)`.
- En local/staging: ≤ 10 peticiones/s.
- Todo lo creado se anota en el reporte (sección "Cómo se hizo").

## 5. Escrituras de las herramientas de nivel 3

`carrera.py`, `flujo.py`, la matriz con `"escritura_ok": true` y `fuzz-api.sh` **escriben datos**. Solo con cuentas
`pentest-*`, nunca con pagos reales (modo de prueba del proveedor), y en producción solo con respaldo confirmado.
`fuzz-api.sh` se niega a correr contra producción salvo `--produccion-autorizada` (y entonces solo GET a 2 peticiones/s).
Todo lo creado se anota en "Lo que creé en la app".

## 6. Service token de Cloudflare Access (para auditar apps detrás de Access)

El dueño lo crea en Zero Trust → Access → Service credentials → **Service Tokens** (duración corta: 1–7 días), y en
la aplicación agrega una política con acción **Service Auth** que incluya solo ese token. Lo exporta en su terminal:
`export CF_ACCESS_CLIENT_ID=… CF_ACCESS_CLIENT_SECRET=…`. Reglas: nunca en archivos, reportes ni el chat; solo por
https; al terminar, **revocarlo**. El service token da acceso a la app, no un usuario de la app: la app puede seguir
exigiendo su propio login (usa además las cuentas de prueba).

## 7. Recomendación

El pentest más completo y sin riesgo es **en local o staging con datos falsos**. En producción, nivel 1 siempre vale la
pena; niveles 2–3 cuando quieras confirmar que lo arreglado de verdad quedó cerrado.
