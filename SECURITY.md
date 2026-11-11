# Política de seguridad / Security policy

## Reportar una falla / Reporting a vulnerability

**No abras un issue público.** Usa el reporte privado de GitHub: pestaña **Security → Report a vulnerability**
(https://github.com/Sibajx/Security-Suite/security/advisories/new).

**Please don't open a public issue.** Use GitHub private reporting: **Security → Report a vulnerability**.

Incluye: qué script o archivo, cómo reproducirlo y qué impacto tiene. Respondo en cuanto pueda (proyecto
personal, sin plazos garantizados). / Include the affected script or file, steps to reproduce and impact.
Best effort response (personal project, no guaranteed timelines).

## Qué cuenta / In scope

- Un script de la suite que ejecute código, escriba o borre fuera de lo que su nivel permite.
- Un script que filtre secretos (tokens, cookies, `CF_ACCESS_*`) en reportes, logs o la terminal.
- Instrucciones de la skill que lleven al agente a atacar un host no autorizado o a saltarse el menú de niveles.

## Qué no cuenta / Out of scope

- Fallas en las herramientas externas (gitleaks, semgrep, sqlmap, nuclei, ffuf…): repórtalas a sus proyectos.
- Falsos positivos o negativos de un chequeo: abre un issue normal.

## Versiones con soporte / Supported versions

Solo la última versión de `main`. / Only the latest `main`.
