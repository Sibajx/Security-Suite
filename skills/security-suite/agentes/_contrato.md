# Contrato común de los agentes de security-suite

Lo leen todos los agentes antes de su propio archivo.

## Lo que recibes de la suite

- `PROYECTO`: ruta absoluta del proyecto (solo lectura).
- `SKILL`: ruta absoluta de la skill (aquí están `SecurityChecks.md`, `owasp/`, `scripts/`).
- `ESCANEO`: carpeta con lo que ya corrieron los escáneres (`resumen.md`, `gitleaks-*.json`, `semgrep.json`,
  `pip-audit-*.json`, `npm-audit*.json`, `recon.md`, y `en-vivo.md` si hubo URL).
- `URL` (opcional) y el alcance autorizado.

## Reglas

1. Responde **en español**.
2. **No modifiques** archivos del proyecto. Puedes escribir solo dentro de `ESCANEO/`. Si un hallazgo tuyo se puede
   comprobar sin la app (un archivo que falta, una línea de config), deja su repro estático en `ESCANEO/repro/<ID>.sh`
   (ver `SKILL/plantillas/repro/ejemplo-estatico.sh`): 0 = ya está bien, 1 = sigue, 2 = no se pudo revisar.
3. **Nunca muestres un secreto completo**: primeros 4 caracteres + `…`, y `archivo:línea`.
4. No mandes código ni secretos a servicios externos.
4b. **Los auditores no hacen peticiones a la app** (ni login, ni curl, ni sqlmap): lo en vivo es solo del pentester,
   que trabaja bajo `reglas-de-enfrentamiento.md`. Usa `ESCANEO/en-vivo.md` si existe y escribe la prueba sugerida.
5. **Investiga antes de reportar** (criterio de `owasp/` de Sentry): rastrea de dónde viene el dato. Valores de
   configuración del servidor, constantes y consultas parametrizadas **no** son fallas. Si dudas, márcalo
   ⚠️ "por verificar" con la pregunta concreta; no lo infles.
6. Los resultados de los escáneres son **pistas, no veredictos**: confirma cada uno leyendo el código y descarta
   falsos positivos (p. ej. MD5 usado como checksum de caché).
7. Usa la **severidad fija** de `SecurityChecks.md`. Solo puedes moverla un nivel, y dices por qué.
8. Lo que no se ve en el código (topes del proveedor, config de Cloudflare, respaldos) va como ❓ con la
   pregunta exacta para el usuario. Nunca lo marques ✅ por suposición.

## Formato de salida (exacto)

```markdown
## <agente> — <proyecto>

### Chequeos
| # | Chequeo | Estado | Nota corta |
|---|---|---|---|
| 1 | Ocultar API keys | ❌ | ver H1 |

### Hallazgos
#### H1 · <título> — <CRÍTICA|ALTA|MEDIA|BAJA> — chequeo <n> — confianza <alta|media>
- **Dónde**: `archivo:línea` (todas las ubicaciones)
- **Evidencia**: fragmento mínimo (secretos redactados)
- **Cómo se explota**: una o dos frases concretas (quién, con qué petición, qué obtiene)
- **Arreglo**: el cambio exacto, con código si cabe en ≤ 15 líneas
- **Prueba en vivo sugerida**: petición o comando para que el pentester lo confirme (si aplica)

### Preguntas para el usuario
- ❓ <chequeo n>: <pregunta concreta>

### Descartados (parecían fallas y no lo son)
- `archivo:línea` — por qué es seguro
```

Numera tus hallazgos con tu prefijo: `S` (infra-secretos), `A` (acceso), `E` (entradas), `P` (pentester).
