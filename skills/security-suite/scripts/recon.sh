#!/usr/bin/env bash
# Reconocimiento del proyecto: stack, archivos clave e inventario de rutas HTTP.
# Solo lee. Uso: bash recon.sh <ruta-proyecto>
set -uo pipefail
P="${1:?uso: recon.sh <ruta-proyecto>}"
cd "$P" || exit 1
EX=(--exclude-dir=node_modules --exclude-dir=.git --exclude-dir=dist --exclude-dir=build --exclude-dir='.venv*' \
    --exclude-dir='venv*' --exclude-dir=env --exclude-dir=site-packages --exclude-dir=__pycache__ --exclude-dir=.next \
    --exclude-dir=.astro --exclude-dir=vendor --exclude-dir=.svelte-kit --exclude-dir=.tox --exclude-dir=coverage)
PRUNE=( \( -name node_modules -o -name .git -o -name dist -o -name build -o -name '.venv*' -o -name 'venv*' -o -name site-packages \
        -o -name .next -o -name .astro -o -name vendor -o -name .svelte-kit -o -name coverage \) -prune -o )

echo "# Reconocimiento: $(basename "$PWD")"
echo
echo "## Archivos clave"
for f in package.json package-lock.json pnpm-lock.yaml yarn.lock bun.lockb pyproject.toml uv.lock poetry.lock \
         requirements*.txt Pipfile Dockerfile* docker-compose*.yml compose*.yml .dockerignore wrangler.toml wrangler.json* \
         astro.config.* next.config.* vite.config.* nuxt.config.* svelte.config.* vercel.json netlify.toml _headers \
         Caddyfile nginx*.conf .env.example .gitignore firebase.json firestore.rules supabase/config.toml .github/workflows; do
  for m in $f; do [ -e "$m" ] && echo "- $m"; done
done
echo
echo "## Stack detectado"
grep -qsi fastapi requirements*.txt pyproject.toml && echo "- FastAPI"
grep -qsi flask requirements*.txt pyproject.toml && echo "- Flask"
grep -qsi django requirements*.txt pyproject.toml && echo "- Django"
grep -qs '"astro"' package.json && echo "- Astro"
grep -qs '"next"' package.json && echo "- Next.js"
grep -qs '"express"' package.json && echo "- Express"
grep -qs '"hono"' package.json && echo "- Hono"
grep -qsE '"(react|vue|svelte)"' package.json && echo "- Front: $(grep -oE '"(react|vue|svelte)"' package.json | tr -d '"' | sort -u | tr '\n' ' ')"
ls wrangler.* >/dev/null 2>&1 && echo "- Cloudflare Workers/Pages"
grep -rqsE "supabase|firebase" "${EX[@]}" --include=*.{js,ts,py,json} . && echo "- Supabase/Firebase (revisar RLS/reglas)"
grep -rqsiE "openai|anthropic|twilio|whatsapp|stripe|mercadopago|resend|sendgrid" "${EX[@]}" --include=*.{js,ts,py} . && \
  echo "- APIs de pago: $(grep -rhoiE "openai|anthropic|twilio|whatsapp|stripe|mercadopago|resend|sendgrid" "${EX[@]}" --include=*.{js,ts,py} . | tr '[:upper:]' '[:lower:]' | sort -u | tr '\n' ' ')"
echo
echo "## Tamaño"
echo "- Archivos de código: $(find . "${PRUNE[@]}" -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.tsx' -o -name '*.jsx' -o -name '*.astro' -o -name '*.vue' -o -name '*.svelte' \) -print | wc -l)"
[ -d .git ] && echo "- Commits en git: $(git rev-list --all --count 2>/dev/null)"
echo
echo "## Inventario de rutas HTTP (para revisar auth/IDOR una por una)"
grep -rnE "@(app|router|[a-z_]+_router|bp|blueprint)\.(get|post|put|patch|delete|route|api_route|websocket)\(" "${EX[@]}" --include=*.py . 2>/dev/null
grep -rnE "\b(app|router|r)\.(get|post|put|patch|delete|all|use)\(\s*['\"\`]/" "${EX[@]}" --include=*.{js,ts,mjs} . 2>/dev/null
find . "${PRUNE[@]}" -path '*/pages/api/*' -type f -print -o -path '*/app/api/*' -name 'route.*' -print 2>/dev/null
grep -rnE "export (const|async function|function) (onRequest(Get|Post|Put|Patch|Delete)?|fetch|scheduled)\b" "${EX[@]}" --include=*.{js,ts} . 2>/dev/null | sed 's/^/cloudflare: /'
grep -rlnE "export (const|async function|function) (GET|POST|PUT|PATCH|DELETE|ALL)\b" "${EX[@]}" --include=*.{js,ts} . 2>/dev/null | sed 's/^/endpoint: /'
exit 0
