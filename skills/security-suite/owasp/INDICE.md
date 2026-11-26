# Índice de las guías OWASP (consulta a demanda)

Las guías son de consulta, **no lectura previa**: ábrelas solo cuando estés investigando un hallazgo de ese tipo y
tengas una duda concreta (¿esto es explotable?, ¿cuál es el arreglo correcto en este framework?). Cada archivo pesa
~10 KB; leer las 8 de un agente "por si acaso" cuesta ~30 000 tokens y no mejora el resultado.

Cómo leer solo lo necesario:
```bash
grep -n '^## ' SKILL/owasp/references/<guía>.md      # ver las secciones
sed -n '<desde>,<hasta>p' SKILL/owasp/references/<guía>.md   # leer solo esa sección
```

| Chequeo | Guía | Para qué abrirla |
|---|---|---|
| 1, 2, 3 | `references/data-protection.md`, `references/cryptography.md` | dónde guardar secretos, cifrado, claves débiles |
| 4, 6 | `references/authorization.md` | patrones de IDOR/BOLA y control por recurso |
| 5, 18 | `references/authentication.md` | hash de contraseñas, sesiones, bloqueo por intentos |
| 7 | `references/api-security.md`, `languages/python.md`, `languages/javascript.md` | validación, mass assignment, particularidades del lenguaje |
| 8 | `references/xss.md` | contextos de salida, CSP |
| 9 | `references/injection.md` | SQL/NoSQL/comandos, identificadores dinámicos |
| 10 | `references/authorization.md` | reglas en la base (multi-tenant) |
| 11, 12 | `references/api-security.md` | rate limiting, recursos caros |
| 13 | `references/file-security.md` | subidas, tipos reales, rutas |
| 14 | `references/csrf.md` | tokens, SameSite, Origin, webhooks |
| 15, 17, 19, 20 | `references/misconfiguration.md`, `references/error-handling.md`, `infrastructure/docker.md` | CORS, headers, debug, contenedores |
| X1 | `references/ssrf.md` | IPs internas, redirecciones, metadatos |
| X2 | `references/deserialization.md` | pickle/YAML/eval, SSTI |
| X3 | `references/file-security.md` | path traversal, open redirect |
| X4, X10 | `references/business-logic.md` | carreras, flujos, precios, pagos |
| X5 | `references/supply-chain.md` | CI/CD, dependencias, acciones sin fijar |
| X6 | `references/logging.md` | qué registrar y qué no |
| X11 | `references/modern-threats.md` (sección LLM Prompt Injection) | inyección de prompt, salida del modelo |
