# Diagnóstico de seguridad — {PROYECTO}

**Fecha:** {FECHA} · **Modo:** {auditoria|pentest|completo} · **Objetivo en vivo:** {URL o "ninguno"} ({ENTORNO}, nivel {N}, autorizado por el usuario: {sí/no})

## Veredicto

{🔴 NO DESPLEGAR | 🟠 DESPLEGAR SOLO TRAS ARREGLAR LO URGENTE | 🟢 LISTO, CON MEJORAS RECOMENDADAS}

**{X}/{Y} chequeos pasan** (de los que aplican) · CRÍTICAS: {n} · ALTAS: {n} · MEDIAS: {n} · BAJAS: {n} · confirmadas en vivo: {n}

{2–3 frases en lenguaje llano: qué tan expuesto está y qué es lo peor que podría pasar hoy.}

## Lo urgente (hacer hoy)

1. **{título}** — {CRÍTICA} — `{archivo:línea}` — {confirmado en vivo / por código}
   {qué hacer en una línea}
2. …

## Los 20 chequeos

| # | Chequeo | Estado | Hallazgos |
|---|---|---|---|
| 1 | Ocultar API keys | ❌ | S1 |
| … | | | |
| X1–X6 | Extras | | |

## Hallazgos

{Todos los hallazgos que sobrevivieron al verificador, ordenados por severidad, con el formato del contrato.
Cada uno indica: CONFIRMADO EN VIVO / CONFIRMADO POR CÓDIGO.}

## Tratamiento: mejores implementaciones para este proyecto

| Prioridad | Mejora | Impacto | Esfuerzo | Plantilla |
|---|---|---|---|---|
| 1 | … | alto | 10 min | `plantillas/…` |

## Preguntas para ti

- ❓ {chequeo}: {pregunta}

## Lo que se revisó y se descartó

- {trampa/falso positivo} — por qué es seguro

## Cómo se hizo

Escáneres: {herramientas y versiones, cuáles faltaron} · Agentes: {cuáles corrieron} · Pruebas en vivo: {resumen,
cuentas/archivos creados y si se limpiaron} · Límites: {lo que no se pudo probar}.
