#!/usr/bin/env bash
# ID: S2
# (Ejemplo: proyecto Python sin lockfile; copia la forma, no el contenido.)
# TITULO: Sin lockfile: el build instala versiones sin revisar
# SEVERIDAD: ALTA
# NIVEL: 0
# ESCRIBE: no
# REQUIERE: PROYECTO
# Estático: revisa el código, no la app.
[ -d "$PROYECTO" ] || { echo "PROYECTO no existe"; exit 2; }
cd "$PROYECTO"
lock=$(ls requirements*.lock uv.lock poetry.lock 2>/dev/null | head -1)
hashes=$(grep -lE -- "--require-hashes|uv sync --frozen|poetry install" Dockerfile 2>/dev/null)
echo "lockfile: ${lock:-ninguno} · Dockerfile instala desde él: ${hashes:+sí}"
[ -n "$lock" ] && [ -n "$hashes" ] && exit 0 || exit 1
