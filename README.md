# 🩺 security-suite

[English](README.en.md) · **Español**

**Una suite de seguridad para Claude Code que revisa tu proyecto de punta a punta: código, secretos, dependencias y el sitio en vivo.** Audita el código, busca secretos (también en
el historial de git), revisa dependencias, prueba la app en vivo y hace pentest **autorizado**. Al final entrega un
diagnóstico con veredicto, puntaje y las mejores implementaciones para tu stack, con código listo.

```
/security-suite
 ├─ Fase 0  Consulta ─────── qué proyecto, qué modo, ¿el sitio es tuyo?, cuentas de prueba
 ├─ Fase 1  Triage ───────── recon + gitleaks + historial de .env + semgrep + pip-audit + npm audit + chequeo en vivo
 ├─ Fase 2  3 auditores ──── infra-secretos · acceso (auth, IDOR, rate limit, gasto) · entradas (SQLi, XSS, subidas…)
 ├─ Fase 3  Pentester ────── confirma en vivo con curl / sqlmap / nuclei / ffuf, dentro de reglas de enfrentamiento
 ├─ Fase 4  Verificador ──── intenta desmentir cada hallazgo grave (cero falsos positivos)
 └─ Fase 5  Diagnóstico ──── 🔴/🟠/🟢 · X/20 chequeos · lo urgente · tratamiento con plantillas
```

## Qué revisa

Los **20 chequeos** de [`SecurityChecks.md`](skills/security-suite/SecurityChecks.md), cada uno con severidad fija,
más 13 extras de nivel senior:

| Secretos | Acceso | Entradas | Infra | Extras |
|---|---|---|---|---|
| 1 API keys ocultas · 2 variables de entorno · 3 keys en git (historial) | 4 ruta admin · 5 auth · 6 permisos/IDOR · 10 reglas DB · 11 rate limiting · 12 límite de gasto | 7 validación · 8 XSS · 9 SQL injection · 13 subidas · 14 CSRF · 15 CORS · 18 cookies | 16 HTTPS · 17 headers · 19 debug · 20 config de producción | SSRF · deserialización/RCE · path traversal · lógica de negocio · CI/CD · registro y monitoreo · subdominios · correo/DNS · políticas de Cloudflare Access · **webhooks de pago** · **chatbots y LLM** · **respaldos contra ransomware** · **GraphQL** |

## Instalación

**Como plugin de Claude Code** (recomendado):
```
/plugin marketplace add Sibajx/Security-Suite
/plugin install security-suite@security-suite
```

**Como skill suelta** (Claude Code y otros agentes compatibles):
```bash
git clone https://github.com/Sibajx/Security-Suite.git ~/security-suite
ln -s ~/security-suite/skills/security-suite ~/.claude/skills/security-suite
```

**Herramientas** (Linux/macOS, sin sudo, en `~/.local/bin`; los binarios se verifican por SHA-256; necesita `uv`):
```bash
bash skills/security-suite/scripts/instalar-herramientas.sh          # instala lo que falte
bash skills/security-suite/scripts/instalar-herramientas.sh --revisar # solo revisa
```
gitleaks · semgrep · pip-audit · sqlmap · nuclei · ffuf, más `dig` y `jq`. Schemathesis y Playwright se usan con `uvx`
(sin instalarlos; Playwright necesita una vez `uvx --with playwright playwright install chromium`). Si falta alguna,
la suite sigue y lo anota en el reporte.

## Uso

En Claude Code, dentro de tu proyecto:

- *"revisa la seguridad de este proyecto"* → auditoría de código
- *"haz un pentest de http://localhost:8000, es mío"* → pruebas en vivo
- *"diagnóstico completo antes de desplegar, la URL de staging es …"* → todo
- *"revisión rápida, la app la hice con Lovable"* → modo `rapido-ia`: los 15 ataques típicos a una app hecha con IA,
  en orden de daño (base de Supabase/Firebase abierta, keys en el bundle, IDOR, precio editable, webhook falso, cupón en
  paralelo, OTP por fuerza bruta, inyección al chatbot…), con puntaje X/15. Ver
  [`rapido-app-ia.md`](skills/security-suite/rapido-app-ia.md)
- *"revisa lo que cambié desde la última auditoría"* → modo `incremental`: solo relanza los agentes del área que
  cambió (`cambios-desde.py`) y hereda el resto del último reporte completo

Los reportes se guardan **en tu escritorio**, fuera de cualquier repo (cámbialo con `SECURITY_SUITE_REPORTES`):
```
Escritorio/Reportes-securitysuite/
├── INDICE.md                      ← semáforo de todos tus sitios
├── VIGIA.md                       ← cambios desde la última revisión semanal
├── midominio_com_RSS/             ← RSS = Reporte Security Suite
│   └── 2026-11-09_2255/
│       ├── DIAGNOSTICO.md
│       └── evidencia/             ← escaneos, en-vivo, nuclei, sqlmap…
└── mi-proyecto_RSS/…
```
Cada corrida agrega una fecha nueva, así ves si el sitio mejoró.

### Herramientas de pentest incluidas (`skills/security-suite/scripts/`)

| Script | Para qué | Nivel |
|---|---|---|
| `en-vivo.sh` | HTTPS, headers, cookies, archivos expuestos; con `CF_ACCESS_CLIENT_ID/SECRET` entra detrás de Cloudflare Access | 1 |
| `subdominios.sh` | Subdominios (Certificate Transparency + 92 nombres típicos), comodín DNS, subdomain takeover | 1 |
| `correo-dns.sh` | SPF, DMARC, DKIM, CAA, DNSSEC: ¿se puede mandar correo falso "de" tu dominio? | 1 |
| `jwt-revisar.py` | `alg=none`, clave débil (offline), sin `exp`, token alterado aceptado | 1–2 |
| `matriz-permisos.py` | Cada ruta × cada rol: IDOR/BOLA, admin abierto, rutas sin auth (genera la plantilla desde OpenAPI) | 2 |
| `carrera.py` | Condición de carrera: N peticiones simultáneas a un canje/cupón/pago | 3 |
| `grabar-flujo.py` + `flujo.py` | Graba un flujo con Playwright y prueba saltar pasos, repetir el último, hacerlo sin empezar | 3 |
| `fuzz-api.sh` | Fuzzing de la API desde su OpenAPI (Schemathesis); solo local/staging | 3 |
| `supabase-rls.py` | Supabase/Firebase: tablas sin RLS, `using (true)`, rol desde `user_metadata`, service_role pública; en vivo solo **cuenta** filas (HEAD, sin descargar datos) | 0–2 |
| `graphql-revisar.py` | GraphQL: introspección abierta, sin límite de profundidad, playground; en vivo manda una introspección y una consulta anidada benigna, sin extraer datos | 0–2 |
| `webhook-falso.py` | Manda tu webhook de pago sin firma y con firma falsa (Stripe, Mercado Pago, PayPal): ¿lo marca como pagado? | 3 |
| `revisar-access.py` | Políticas de Cloudflare Access que en realidad dejan entrar a cualquiera (Include con PIN, Everyone, gmail.com…) | 0 (lee la config) |
| `reverificar.py` | Después de arreglar: vuelve a correr la reproducción de cada hallazgo (`evidencia/repro/`) y arma la tabla antes → ahora | el del repro |
| `vigia.sh` + `instalar-vigia.sh` | Revisión semanal pasiva de todos tus sitios y aviso de lo que cambió (`VIGIA.md`) | 1 |

Cada hallazgo confirmado deja su script en `evidencia/repro/<ID>.sh|.py` (sale 0 = arreglado, 1 = sigue,
2 = no se pudo probar; ejemplos en [`plantillas/repro/`](skills/security-suite/plantillas/repro/)). Al decir
"ya lo arreglé", la suite corre `reverificar.py` contra la versión nueva. Prueba del ejecutor: `bash tests/probar-reverificar.sh`.

Para un repo: [`plantillas/vigia-github-actions.yml`](skills/security-suite/plantillas/vigia-github-actions.yml)
corre gitleaks, auditoría de dependencias y la revisión pasiva cada lunes y abre un issue si algo empeora.

## Reglas de enfrentamiento y niveles

Antes de cualquier prueba en vivo la suite muestra un **menú de niveles** y tú eliges:

| Nivel | Qué hace | Qué deja |
|---|---|---|
| 1 · Revisión pasiva | HTTPS, headers, cookies, rutas expuestas: lo mismo que un navegador | nada |
| 2 · Confirmación | prueba cada hallazgo con payloads inofensivos (SQLi sin extraer, IDOR entre cuentas de prueba, CORS, rate limit, nuclei) | sesiones de prueba |
| 3 · Ataque controlado | + descubrimiento con ffuf, cuentas `pentest-*`, escalada de rol, subida de un .txt, CSRF, SSRF al propio host | cuentas/archivos `pentest-*` (se borran) |

Tus dominios van en `~/.config/security-suite/autorizados.yml` con el nivel máximo que permites (ejemplo en
[`autorizados.ejemplo.yml`](skills/security-suite/autorizados.ejemplo.yml)); ese archivo es personal y no va al repo.


El pentest **solo** se hace contra sitios tuyos o con autorización escrita del dueño. Antes de cualquier prueba en
vivo la suite pregunta y lo anota en el reporte. Hay tres niveles: pasivo, confirmación y activo. En producción solo
se permite el pasivo, salvo un OK explícito; nunca hay DoS, extracción de datos ni shells. Detalle en
[`reglas-de-enfrentamiento.md`](skills/security-suite/reglas-de-enfrentamiento.md).

### Uso responsable

Usar la suite contra sistemas que no son tuyos, o sin permiso **por escrito** de su dueño, puede ser delito en tu
país. Tú eres responsable de cómo la usas. Se entrega "tal cual", sin garantías (ver [`LICENSE`](LICENSE)). Los
autores no responden por daños, caídas o pérdida de datos causados por pruebas en vivo; por eso el nivel por
defecto es pasivo y en producción se pide respaldo antes de los niveles que escriben.

¿Encontraste una falla en la suite misma? Ver [`SECURITY.md`](SECURITY.md).

Los agentes **no modifican** tu proyecto. Los arreglos los hace la sesión principal, con tu OK, y después vuelve a
auditar.

## Tratamiento incluido

[`mejores-practicas.md`](skills/security-suite/mejores-practicas.md) y [`plantillas/`](skills/security-suite/plantillas):
- módulo de endurecimiento para FastAPI (argon2, slowapi con IP real detrás de Cloudflare, cookies `__Host-`,
  headers + CSP, CORS estricto, errores sin traceback, settings que fallan sin secretos);
- workflow de GitHub Actions (gitleaks + semgrep + auditoría de dependencias);
- pre-commit con gitleaks, Dependabot, `.dockerignore`, Dockerfile no root, `_headers` para Cloudflare, `security.txt`;
- [Next.js + Supabase + Stripe](skills/security-suite/plantillas/nextjs-supabase.md): service_role solo en el servidor,
  RLS por dueño, `/admin` en el middleware, precio del servidor, webhook firmado e idempotente, OTP, chatbot, subidas, headers;
- [Express](skills/security-suite/plantillas/express.md): helmet, rate limit con IP real, webhook con cuerpo crudo,
  zod estricto, cookies `__Host-`, CSRF por Origin, dueño en el where.

### Cuánto gasta

Los agentes leen resúmenes, no los JSON crudos (`escaneo-compacto.md`); cada auditor recibe solo sus chequeos
(`chequeos.py`) y consulta las guías de OWASP a demanda (`owasp/INDICE.md`). El modo `incremental` evita volver a
auditar lo que no cambió, y en presupuesto `economico` el pentester usa un modelo más barato. Los auditores y el
verificador siempre usan el modelo de la sesión: ahí se juega la calidad. Medición determinista del ahorro (83% menos contexto por auditor): [`docs/medicion-tokens.md`](docs/medicion-tokens.md) (`tests/medir-lectura.py`).

## Pruebas

Ejemplos de salida (corridas reales, calificadas): [modo completo (FastAPI)](docs/ejemplo-diagnostico.md) · [modo `rapido-ia` (Next.js)](docs/ejemplo-rapido-ia.md) · [auditoría (Django)](docs/ejemplo-django.md).

**Como barrera de CI, sin modelo:** la parte determinista (secretos, reglas de semgrep, Supabase, GraphQL) corre sola en cada push con la [GitHub Action](docs/accion-ci.md).

`tests/` genera una app FastAPI con **31 fallas plantadas y 6 trampas**, más una app Next.js + Supabase con 17
fallas típicas de apps hechas con IA, y una hoja de respuestas para medir la suite
o comparar modelos. Ver [`tests/README.md`](tests/README.md).

## Créditos

Las referencias OWASP de `skills/security-suite/owasp/` vienen de
[getsentry/skills](https://github.com/getsentry/skills) (Apache 2.0), derivadas del
[OWASP Cheat Sheet Series](https://cheatsheetseries.owasp.org/). Ver `NOTICE`. El resto está bajo licencia MIT.

> ⚠️ Ninguna herramienta garantiza que un sitio sea seguro. La suite reduce el riesgo y dice qué revisó y qué
> quedó fuera; las decisiones finales son tuyas.
