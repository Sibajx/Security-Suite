# security-suite como GitHub Action (barrera de CI, sin modelo)

La auditoría completa necesita los agentes (un modelo). Pero la **parte determinista** —secretos en git, reglas de
semgrep de la suite (webhook sin firma, service_role pública, precio del cliente, open redirect, IDOR, LLM…),
Supabase/Firebase abierto y GraphQL inseguro— corre sola y sirve de barrera en cada push.

## Uso

En tu repo, `.github/workflows/seguridad.yml`:

```yaml
name: seguridad
on: [push, pull_request]
jobs:
  security-suite:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5        # para gitleaks
        with: { go-version: "1.22" }
      - uses: Sibajx/Security-Suite@main
        with:
          proyecto: .                    # opcional, por defecto el repo
```

El job **falla** si hay un hallazgo bloqueante (secretos en git, webhook sin firma, tabla sin RLS, introspección
GraphQL abierta…) y deja el detalle en el resumen del run y en `security-suite-informe.md`.

## Qué revisa y qué no

| Revisa (sin modelo) | No revisa (necesita la skill completa) |
|---|---|
| Secretos en el árbol y el historial (gitleaks) | IDOR confirmado entre cuentas |
| Reglas de semgrep de la suite | Lógica de negocio, flujos, carreras |
| Supabase/Firebase: RLS, `using(true)`, service_role pública | Auth, sesiones, autorización por recurso a fondo |
| GraphQL: introspección y profundidad (estático) | Todo lo que sale solo en vivo |

Para la auditoría completa, corre la skill `security-suite` desde Claude Code sobre el proyecto.
