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
