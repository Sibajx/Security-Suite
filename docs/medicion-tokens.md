# Medición de tokens: v1.1 vs v1.2

> Generado con `tests/medir-lectura.py` sobre la evidencia de la corrida del 2026-11-27 (fixture FastAPI).
> Es determinista: mide el contexto que cada auditor lee antes de auditar, no una corrida de agentes.


Tokens ≈ caracteres/4. 'checks' = SecurityChecks completo vs solo los del agente; 'owasp' = guías por adelantado vs INDICE; 'escaneo' = JSON crudos vs escaneo-compacto.md.

| Agente | Versión | contrato | agente | checks | owasp | escaneo | total (tokens) |
|---|---|---|---|---|---|---|---|
| infra-secretos | v1.1 | 729 | 781 | 3250 | 0 | 6597 | **11358** |
| infra-secretos | v1.2 | 878 | 817 | 1424 | 550 | 426 | **4094** |
| acceso | v1.1 | 729 | 1027 | 3250 | 11119 | 6597 | **22724** |
| acceso | v1.2 | 878 | 1104 | 1016 | 550 | 426 | **3973** |
| entradas | v1.1 | 729 | 1010 | 3250 | 25187 | 6597 | **36775** |
| entradas | v1.2 | 878 | 1009 | 1110 | 550 | 426 | **3973** |

**Total 3 auditores:** v1.1 ≈ 70,856 tokens · v1.2 ≈ 12,039 tokens · **83% menos** de contexto de lectura por corrida (sin contar el código del proyecto, igual en ambas).

_Mide lo que cada agente lee antes de auditar; el ahorro real por corrida depende además de cuánto código abra cada uno, que no cambia entre versiones._

## Además, de la corrida completa real (con agentes, 2026-11-27)

- FastAPI modo completo: 31/31 fallas, 0 trampas, **618k tokens nuevos** en los 5 subagentes.
- Next.js modo rapido-ia: 17/17, **75k tokens nuevos** (un solo agente).
- La medición estática de arriba explica de dónde sale buena parte del ahorro: los auditores reciben 83% menos texto de contexto.
