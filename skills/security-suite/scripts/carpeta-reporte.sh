#!/usr/bin/env bash
# Crea y devuelve la carpeta de un reporte nuevo:
#   <Escritorio>/Reportes-securitysuite/<nombre>_RSS/<AAAA-MM-DD_HHMM>/{DIAGNOSTICO.md, evidencia/}
# <nombre> = dominio (puntos → "_") o nombre de la carpeta del proyecto. RSS = Reporte Security Suite.
# Base configurable con SECURITY_SUITE_REPORTES. Uso: bash carpeta-reporte.sh <url|dominio|ruta-proyecto>
#   bash carpeta-reporte.sh --base   → solo imprime (y crea) la carpeta Reportes-securitysuite
set -euo pipefail
obj="${1:?uso: carpeta-reporte.sh <url|dominio|ruta>}"
if [ -n "${SECURITY_SUITE_REPORTES:-}" ]; then BASE="$SECURITY_SUITE_REPORTES"
else
  esc=$(xdg-user-dir DESKTOP 2>/dev/null || true)
  [ -n "$esc" ] && [ "$esc" != "$HOME" ] && [ -d "$esc" ] || for d in "$HOME/Desktop" "$HOME/Escritorio"; do [ -d "$d" ] && esc="$d" && break; done
  [ -n "$esc" ] && [ -d "$esc" ] || esc="$HOME"
  BASE="$esc/Reportes-securitysuite"
fi
if [ "$obj" = "--base" ]; then mkdir -p "$BASE"; echo "$BASE"; exit 0; fi
if [ -d "$obj" ]; then nombre=$(basename "$(cd "$obj" && pwd)")
else nombre=$(echo "$obj" | sed -E 's#^[a-z]+://##; s#[/:?].*$##'); fi
nombre=$(echo "$nombre" | tr '.' '_' | tr -cd 'A-Za-z0-9_-')
D="$BASE/${nombre}_RSS/$(date +%Y-%m-%d_%H%M)"
mkdir -p "$D/evidencia"; chmod 700 "$BASE" 2>/dev/null || true
echo "$D"
