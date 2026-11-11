#!/usr/bin/env bash
# Instala las herramientas de la suite en ~/.local/bin (sin sudo). Linux y macOS, amd64/arm64.
# Binarios de GitHub se verifican con la suma SHA-256 que publica cada proyecto.
# Uso: bash instalar-herramientas.sh            (instala lo que falte)
#      bash instalar-herramientas.sh --revisar  (solo dice qué hay y qué falta)
set -euo pipefail

BIN="${HOME}/.local/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

case "$(uname -s)" in Linux) OS=linux ;; Darwin) OS=macOS ;; *) echo "SO no soportado"; exit 1 ;; esac
case "$(uname -m)" in x86_64|amd64) ARCH=amd64; GLARCH=x64 ;; aarch64|arm64) ARCH=arm64; GLARCH=arm64 ;; *) echo "Arquitectura no soportada"; exit 1 ;; esac
OSL=$(echo "$OS" | tr '[:upper:]' '[:lower:]')   # linux / macos
GLOS=$OSL; [ "$OS" = macOS ] && GLOS=darwin

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

ultima_version() { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | grep -o '"tag_name": *"v[^"]*"' | grep -o 'v[^"]*' | head -1 | sed 's/^v//'; }

# instalar_github <repo> <binario> <archivo-con-%s-para-version> <checksums-con-%s>
instalar_github() {
  local repo=$1 bin=$2 patron=$3 patron_sums=$4 v f sums tmp esperado real
  v=$(ultima_version "$repo"); [ -n "$v" ] || { echo "  ✗ no pude leer la versión de $repo"; return 1; }
  f=$(printf "$patron" "$v"); sums=$(printf "$patron_sums" "$v")
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/$f" "https://github.com/$repo/releases/download/v$v/$f"
  curl -fsSL -o "$tmp/sums" "https://github.com/$repo/releases/download/v$v/$sums"
  esperado=$(grep " \*\?$f\$" "$tmp/sums" | awk '{print $1}')
  real=$(sha256 "$tmp/$f")
  [ -n "$esperado" ] && [ "$esperado" = "$real" ] || { echo "  ✗ suma SHA-256 no coincide para $f — no se instala"; rm -rf "$tmp"; return 1; }
  case "$f" in *.zip) unzip -oq "$tmp/$f" "$bin" -d "$tmp" ;; *) tar xzf "$tmp/$f" -C "$tmp" "$bin" ;; esac
  install -m755 "$tmp/$bin" "$BIN/$bin"; rm -rf "$tmp"
  echo "  ✓ $bin $v (SHA-256 verificado)"
}

instalar_uv_tool() {
  command -v uv >/dev/null || { echo "  ✗ falta uv (https://docs.astral.sh/uv/) para instalar $1"; return 1; }
  uv tool install --quiet "$1" && echo "  ✓ $1"
}

declare -A PARA=(
  [gitleaks]="secretos en el historial de git"
  [semgrep]="análisis estático (OWASP)"
  [pip-audit]="dependencias Python con CVE"
  [sqlmap]="confirmar inyección SQL (pentest)"
  [nuclei]="plantillas de vulnerabilidades conocidas (pentest)"
  [ffuf]="descubrir rutas y archivos expuestos (pentest)"
)
ORDEN=(gitleaks semgrep pip-audit sqlmap nuclei ffuf)

echo "Herramientas de security-suite:"
falta=()
for t in "${ORDEN[@]}"; do
  if command -v "$t" >/dev/null; then echo "  ✓ $t — ${PARA[$t]}"; else echo "  · $t — FALTA — ${PARA[$t]}"; falta+=("$t"); fi
done
for t in curl git npm dig jq; do command -v $t >/dev/null || echo "  · $t no está (algunas pruebas se saltarán)"; done
command -v uvx >/dev/null && echo "  ✓ uvx — schemathesis (fuzz-api.sh) y playwright (grabar-flujo.py) se usan con uvx, sin instalarlos" \
  || echo "  · uvx no está — sin fuzzing ni grabación de flujos (https://docs.astral.sh/uv/)"

[ "${1:-}" = "--revisar" ] && { [ ${#falta[@]} -eq 0 ]; exit $?; }
[ ${#falta[@]} -eq 0 ] && { echo "Todo instalado."; exit 0; }

echo; echo "Instalando: ${falta[*]}"
for t in "${falta[@]}"; do
  case $t in
    gitleaks) instalar_github gitleaks/gitleaks gitleaks "gitleaks_%s_${GLOS}_${GLARCH}.tar.gz" "gitleaks_%s_checksums.txt" || true ;;
    nuclei)   instalar_github projectdiscovery/nuclei nuclei "nuclei_%s_${OSL}_${ARCH}.zip" "nuclei_%s_checksums.txt" || true ;;
    ffuf)     instalar_github ffuf/ffuf ffuf "ffuf_%s_${OSL}_${ARCH}.tar.gz" "ffuf_%s_checksums.txt" || true ;;
    semgrep|pip-audit|sqlmap) instalar_uv_tool "$t" || true ;;
  esac
done
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "Agrega ~/.local/bin a tu PATH." ;; esac
