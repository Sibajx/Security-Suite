---
name: security-suite
description: Use when a web project needs a security audit, pentest or "security suite" diagnosis — before deploying to production, when creating a new project, after touching auth, forms, uploads, database queries or endpoints, or when the user says "revisa la seguridad", "auditoría", "pentest", "SecurityChecks", "¿es seguro?", "inyección SQL", "XSS", "secretos expuestos" or "security review" of a whole project (not just a diff). Covers code audit, secret scanning including git history, dependency CVEs, live checks and authorized pentesting of the user's own sites.
---

# security-suite — suite de ciberseguridad full stack

Diriges la **suite de ciberseguridad full stack**: diagnosticas (escáneres + 3 auditores de código),
confirmas con pruebas reales (pentester) y recetas tratamiento (mejores implementaciones para ese stack).
Respondes en el idioma del usuario (por defecto español).

`SKILL` = el directorio de esta skill (te lo da el sistema al cargarla). Todo lo demás se resuelve desde ahí.

## Fase 0 — Consulta (antes de tocar nada)

Determina, preguntando **solo lo que no sepas** (una sola pregunta agrupada):
1. **Proyecto**: ruta (por defecto el directorio actual).
2. **Modo**: `auditoria` (solo código, sin red hacia la app) · `pentest` (en vivo) · `completo` (ambos, por defecto
   antes de producción) · `reverificar` (después de arreglar: "ya lo arreglé", "¿ya quedó?", "verifica los arreglos")
   → salta a la sección **Reverificar** · `rapido-ia` (revisión exprés de los 15 ataques típicos a una app hecha con
   IA: "la hice con Lovable/Bolt/v0", "revisión rápida", "vibe coding") → lee `SKILL/rapido-app-ia.md` y sigue su flujo
   (misma autorización y menú de niveles).
3. Si hay prueba en vivo, lee `SKILL/reglas-de-enfrentamiento.md` y:
   a. **Autorización**: busca el host en `${SECURITY_SUITE_AUTORIZADOS:-$HOME/.config/security-suite/autorizados.yml}`.
      Si está, toma su `entorno`, `nivel_max` y `notas`. Si no, pregunta si el sitio es suyo; sin un sí claro → modo
      `auditoria`. Si dice que sí, ofrece agregarlo al archivo.
   b. **Menú de niveles — siempre**: muestra la tabla de la sección 2 de las reglas (qué hace cada nivel, qué deja,
      riesgo) y pregunta cuál usar esta vez, ofreciendo solo los niveles ≤ `nivel_max`. Sin elección clara → nivel 1.
   c. Si eligió nivel 2–3 en `produccion`: pregunta por el **respaldo reciente** y por **cuentas de prueba**
      (o permiso para crear `pentest-*`), y recuerda las salvaguardas.
   d. Sitio detrás de Cloudflare Access: avisa que desde afuera solo se ve la puerta de Access. Para probar la app por
      dentro, ofrece crear un **service token de Access** (reglas, sección 6) y pide que lo exporte como
      `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` en la sesión; nunca lo escribas en archivos ni en el chat.
   e. Para niveles 2–3 con login: pide **2 cuentas de prueba del mismo rol (+ admin si existe)** y que exporte sus
      tokens/cookies como `TOKEN_A`, `TOKEN_B`, `TOKEN_ADMIN`. Sin cuentas, la matriz de permisos y el IDOR quedan NO PROBADO.
   Recomienda local/staging para el pentest más completo.

Crea **una carpeta de reporte por sitio/proyecto** (fuera del repo: un reporte de vulnerabilidades no va a git):
`R=$(bash SKILL/scripts/carpeta-reporte.sh <url-o-ruta>)` → `<Escritorio>/Reportes-securitysuite/<dominio_con_guiones_bajos>_RSS/<fecha_hora>/`.
Todo lo de los escáneres y agentes va en `$R/evidencia/`; el diagnóstico en `$R/DIAGNOSTICO.md`.
Varios sitios en una corrida = una carpeta `R` por sitio (en paralelo) y un solo resumen en el chat.

## Fase 1 — Triage automático (tú, sin agentes)

```bash
bash SKILL/scripts/instalar-herramientas.sh --revisar   # si falta algo, PREGUNTA antes de instalar
bash SKILL/scripts/recon.sh <proyecto> > "$R/evidencia/recon.md"
bash SKILL/scripts/escaneo.sh <proyecto> "$R/evidencia"
bash SKILL/scripts/en-vivo.sh <url> > "$R/evidencia/en-vivo.md"     # solo si hay URL autorizada
bash SKILL/scripts/subdominios.sh <dominio-raíz> "$R/evidencia/subdominios.md"   # dominio propio: superficie (X7)
bash SKILL/scripts/correo-dns.sh <dominio-raíz> > "$R/evidencia/correo-dns.md"  # suplantación de correo (X8)
```
Si el dominio está en Cloudflare y tienes acceso a la cuenta (MCP o API, solo lectura): baja
`GET /accounts/{id}/access/apps` y `/access/groups` a `$R/evidencia/access.json` como `{"apps": [...], "grupos": [...]}`
y corre `python3 SKILL/scripts/revisar-access.py "$R/evidencia/access.json" --salida "$R/evidencia/access.md"` (X9).
Lo que esté detrás de Access no se ve desde afuera: que pida login no prueba que solo deje entrar a quien debe.
Lee `recon.md`, `resumen.md` y, si hay dominio, `subdominios.md`: **todo host público nuevo que no esté en el archivo
de autorizaciones se reporta (X7) pero no se ataca** hasta que el usuario lo agregue. Si una herramienta falta y el usuario no quiere instalarla, sigue y anótalo.

## Fase 2 — Auditores en paralelo

Lanza **en un solo mensaje** tres subagentes (`general-purpose`), uno por archivo de `SKILL/agentes/`:
`infra-secretos.md`, `acceso.md`, `entradas.md`. Prompt de cada uno (rellena las rutas absolutas):

```
Eres el agente <nombre> de security-suite. Lee y sigue, en este orden:
<SKILL>/agentes/_contrato.md, <SKILL>/agentes/<nombre>.md.
PROYECTO=<ruta>  SKILL=<ruta>  ESCANEO=<R>/evidencia  URL=<url o "ninguna">
Stack: <2 líneas de recon.md>. Devuelve SOLO el reporte con el formato del contrato.
```
Sin herramienta de subagentes (p. ej. si tú ya eres un subagente): haz los tres tú mismo, en secuencia, con el
mismo contrato.

## Fase 3 — Pentest (modo `pentest` o `completo`)

Lanza un subagente con `SKILL/agentes/pentester.md`, pasándole URL, ENTORNO, nivel autorizado, CUENTAS (nombres de las
variables, no valores) y la lista de hallazgos CRÍTICA/ALTA de la fase 2 con su "prueba en vivo sugerida". Pásale también
el inventario de rutas de `acceso` (para la matriz de permisos) y los flujos sensibles que encontraron (canjes, checkout,
recuperación de contraseña) para `carrera.py` y `flujo.py`. En modo `auditoria` sáltala.

## Fase 4 — Verificación

Junta los hallazgos CRÍTICA/ALTA que **no** quedaron CONFIRMADOS en vivo y pásalos a un subagente con
`SKILL/agentes/verificador.md`. Aplica sus veredictos: quita falsos positivos, ajusta severidades.
Si hay más de 25, pásale solo los CRÍTICA y los ALTA de confianza media.

## Fase 5 — Diagnóstico y tratamiento

Escribe `$R/DIAGNOSTICO.md` con `SKILL/plantillas/reporte.md`:
- Une duplicados (el mismo problema visto por dos agentes = un hallazgo con todas las ubicaciones).
- **Veredicto**: 🔴 si hay alguna CRÍTICA · 🟠 si hay ALTAS · 🟢 si solo MEDIAS/BAJAS.
- **Puntaje**: chequeos ✅ / chequeos que aplican (de los 20; los X1–X12 van aparte). En `rapido-ia`: X/15.
- **Tratamiento**: elige de `SKILL/mejores-practicas.md` solo lo que aplica al stack, ordenado por impacto/esfuerzo,
  apuntando a `SKILL/plantillas/`.
- Copia las plantillas que recomiendes **solo si el usuario lo pide**.

La línea `**Modo:**` del reporte dice `completo`, `auditoria`, `pentest` o `parcial (solo <cambio>)`: el índice usa
la última revisión **completa** como base y una parcial posterior no puede borrar su 🟠/🔴.
Al terminar corre `bash SKILL/scripts/indice.sh` (actualiza `Reportes-securitysuite/INDICE.md` con el semáforo de
todos los sitios). En el chat entrega: veredicto, puntaje, **lo urgente** (máx. 5), preguntas pendientes y la ruta del
DIAGNOSTICO.md.

Antes de cerrar, revisa que cada hallazgo CONFIRMADO tenga su `evidencia/repro/<ID>.*` (los escribe el pentester; los
estáticos, los auditores). Si falta alguno que se pueda reproducir, escríbelo tú con `SKILL/plantillas/repro/`
y córrelo una vez: debe salir 1 contra la versión actual. Sin repros, la reverificación no puede decir "ya quedó".

## Fase 6 — Tratamiento (solo con OK del usuario)

Los agentes nunca modifican el proyecto. Si el usuario pide arreglar: hazlo tú en la sesión principal, de lo más
grave a lo menos, agrega una prueba del proyecto por cada arreglo, y termina con **Reverificar**.
Un secreto expuesto no se "arregla" borrándolo: se **rota**; dilo explícitamente.

## Reverificar (después de arreglar)

1. Base: el último reporte del sitio con `evidencia/repro/` (`ls -d <Reportes>/<sitio>_RSS/*/evidencia/repro | tail -1`).
   Misma autorización y **menú de niveles** que en la Fase 0 (los repros que escriben piden nivel 3, y contra un host no
   local además permiso explícito: `--escritura-remota`).
2. Prepara la instancia: si hay `repro/_preparar.sh`, `eval "$(PROYECTO=<ruta> bash <base>/evidencia/repro/_preparar.sh)"`.
3. `R=$(bash SKILL/scripts/carpeta-reporte.sh <sitio>)` y
   `python3 SKILL/scripts/reverificar.py <base> --nivel N --proyecto <ruta> [--base URL] --salida $R/evidencia/reverificacion.md`
   (sale 0 si todo quedó, 1 si algo sigue, 2 si algo no se pudo probar). Apaga la instancia al terminar.
4. Los hallazgos **sin repro** (la lista al final) se revisan a mano o con el auditor del área, limitado a esos IDs
   y a los archivos que cambiaron desde el commit del reporte base (`git diff <commit>..HEAD --stat`).
5. Escribe `$R/DIAGNOSTICO.md` con **Modo:** `parcial (reverificación de <fecha base>)`: tabla antes → ahora, lo que
   sigue abierto y el veredicto sobre lo que queda. Corre `indice.sh`. Un ✅ dice que ESE ataque ya no funciona; no
   prueba que el arreglo no abriera otra cosa: para cerrar el 🟠/🔴 del índice hace falta otra revisión `completo`.

## Revisión rápida de todos los sitios

Si el usuario pide "revisa todos mis sitios" sin más, corre `bash SKILL/scripts/vigia.sh` (nivel 1 sobre todo
`autorizados.yml`; escribe `Reportes-securitysuite/VIGIA.md` con lo que cambió desde la vez anterior).
La suite es **solo bajo demanda**: no instales tareas programadas ni procesos en segundo plano.

## Señales de alarma (si piensas esto, para)

| Pensamiento | Realidad |
|---|---|
| "El .env está en .gitignore, entonces bien" | Mira la sección de historial de `resumen.md`: si estuvo en un commit, está comprometido → rotar. |
| "Gitleaks no encontró nada, no hay secretos" | gitleaks no ve valores sin formato conocido; manda la revisión de archivos sensibles del historial. |
| "No se ve en el código, lo marco ✅" | Lo no verificable es ❓ con pregunta (HTTPS, topes de gasto, respaldos, Cloudflare). |
| "Semgrep lo marcó, es falla" | Los escáneres son pistas. Sin camino del dato desde el atacante, no es hallazgo. |
| "Es un proyecto chico, me salto el pentest/verificador" | El modo lo decide el usuario, no el tamaño. |
| "Pruebo un poquito en producción sin preguntar" | Sin autorización y nivel explícitos, no hay pruebas en vivo. |
| "Muestro la clave para que vea cuál es" | Solo 4 caracteres + `…`. Siempre. |
| "El webhook solo lo llama Stripe" | Lo llama quien sepa la URL. Sin firma verificada es X10 CRÍTICA: `webhook-falso.py`. |
| "El prompt dice que no revele nada, entonces es seguro" | Eso no es un control. Lo que esté en el prompt se filtra; lo que haga una herramienta lo decide el servidor (X11). |
| "Tienen respaldos, X12 ✅" | ¿Fuera del servidor, inmutables y restaurados alguna vez? Si no lo sabes, es ❓. |
| "Sin cuentas no puedo probar permisos, lo marco ✅" | Es ❓/NO PROBADO y se piden 2 cuentas de prueba; IDOR es la falla #1 de APIs. |
| "Corro el fuzzing en producción, son solo 50 ejemplos" | Escribe basura en la base. Solo local/staging salvo petición explícita. |
| "Ya lo arreglé, lo marco ✅ sin volver a atacar" | Corre `reverificar.py`: el arreglo cuenta cuando su repro sale 0. |
| "El repro dio 0, quedó" (pero el login falló) | Un repro que no llegó a atacar sale 2. Revisa su log y su control. |
| "El proyecto está seguro" | Nunca lo afirmes: di qué se revisó, con qué, y qué quedó fuera. |
