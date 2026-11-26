# Plantillas cortas

## `.pre-commit-config.yaml` — bloquea secretos antes de cada commit
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.1
    hooks:
      - id: gitleaks
```
Activar: `pipx install pre-commit && pre-commit install`.

## `.github/dependabot.yml` — PRs automáticos de actualizaciones
```yaml
version: 2
updates:
  - package-ecosystem: pip
    directory: "/"
    schedule: { interval: weekly }
  - package-ecosystem: npm
    directory: "/"
    schedule: { interval: weekly }
  - package-ecosystem: github-actions
    directory: "/"
    schedule: { interval: monthly }
  - package-ecosystem: docker
    directory: "/"
    schedule: { interval: monthly }
```

## `.dockerignore`
```
.git
.env
.env.*
!.env.example
*.pem
*.key
*.db
*.sqlite*
node_modules
.venv
__pycache__
tests
```

## `Dockerfile` (Python) endurecido
```dockerfile
FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN useradd --create-home --uid 10001 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=app:app . .
USER app
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
```

## `docker-compose.yml`: la base de datos sin puertos publicados
```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD_FILE: /run/secrets/db_password
    secrets: [db_password]
    # sin "ports:" → solo la ve la red interna de compose
secrets:
  db_password:
    file: ./secrets/db_password.txt   # en .gitignore
```

## `public/_headers` (Cloudflare Pages / Workers static assets, Astro estático)
```
/*
  Content-Security-Policy: default-src 'self'; img-src 'self' data: https:; script-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'; base-uri 'self'
  Strict-Transport-Security: max-age=31536000; includeSubDomains
  X-Content-Type-Options: nosniff
  Referrer-Policy: strict-origin-when-cross-origin
  Permissions-Policy: camera=(), microphone=(), geolocation=()
  X-Frame-Options: DENY
```

## `public/.well-known/security.txt`
```
Contact: mailto:seguridad@tudominio.com
Expires: 2027-12-31T23:59:59Z
Preferred-Languages: es, en
```

## Respaldo a prueba de ransomware (X12): `respaldo.sh` + bucket con bloqueo

Idea: el servidor de la app **solo puede escribir** respaldos; no puede borrarlos ni sobrescribirlos. Aunque un
atacante tome el servidor (o lo cifre un ransomware), las copias de los últimos días sobreviven.

1. Bucket **en otra cuenta o proveedor** (Cloudflare R2, Backblaze B2, S3) con retención/bloqueo de objetos
   (R2: *Bucket lock rules*; B2 y S3: *Object Lock* en modo compliance) de 14–30 días.
2. Credencial para el servidor con permiso de **escribir** objetos, sin permiso de borrar ni de cambiar el bloqueo.
   La credencial de administración del bucket nunca está en el servidor.
3. Cron diario:
```bash
#!/usr/bin/env bash
# respaldo.sh — volcado comprimido y cifrado, subido con nombre por fecha (nunca se sobrescribe).
set -euo pipefail
f="db-$(date -u +%Y%m%dT%H%M%SZ).sql.gz.age"
pg_dump "$DATABASE_URL" | gzip | age -r "$RESPALDO_CLAVE_PUBLICA" > "/tmp/$f"   # la clave privada vive fuera del servidor
rclone copyto "/tmp/$f" "respaldos:mi-bucket/db/$f" --s3-no-check-bucket
rm -f "/tmp/$f"
```
4. Una vez al mes: **restaurar** el último respaldo en una base desechable y anotar la fecha. Un respaldo que nunca
   se restauró no cuenta.
5. 2FA en el hosting, en la base gestionada y en la cuenta del bucket.
