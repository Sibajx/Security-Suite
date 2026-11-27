# Diagnóstico de seguridad — tienda-django (fixture Django + DRF)

> Corrida real de los 3 auditores (modo auditoría) sobre `tests/crear-fixture-django.sh`, el 2026-11-27.
> Calificación con `tests/calificar.py --esperado tests/esperado-django.json`: 20/20 fallas, 0 trampas, 0 secretos.
> Demuestra que los auditores no están sesgados a FastAPI/Next.js.


**Fecha:** 2026-11-27 · **Commit:** `ff988cd06b` · **Modo:** auditoria · **Objetivo en vivo:** ninguno

## Veredicto

🔴 **NO DESPLEGAR** · CRÍTICAS: 10 · ALTAS: 9 · MEDIAS: 2

## Hallazgos (unidos de los 3 auditores)

- **D01** `.env` con `SECRET_KEY`, `DATABASE_URL` y `STRIPE_SECRET_KEY` en el **historial** de git (commits inicio/quitar .env) — CRÍTICA — chequeo 3 — rotar las tres.
- **D02** `SECRET_KEY` con valor por defecto `changeme` y `DEBUG = True` fijo — CRÍTICA — chequeos 2, 19 — `tienda/settings.py`.
- **D03** `ALLOWED_HOSTS = ["*"]` — ALTA — chequeo 20 — `tienda/settings.py`.
- **D04** SQL injection por `%` en `buscar` (`cursor.execute(... % q)`) — CRÍTICA — chequeo 9 — `pedidos/views.py:14`.
- **D05** Mass assignment: serializer `fields="__all__"` deja al cliente mandar `usuario`, `pagado`, `total` — CRÍTICA — chequeos 7/6 — `pedidos/serializers.py`.
- **D06** IDOR en `ver_pedido` y `perfil`: `get_object_or_404(Pedido, pk=pk)` sin filtrar por el usuario — CRÍTICA — chequeo 6 — `pedidos/views.py`.
- **D07** `PedidoViewSet` con `AllowAny` y `queryset = Pedido.objects.all()`: devuelve los pedidos de todos sin auth — CRÍTICA — chequeos 4/6 — `pedidos/api.py`.
- **D08** `@csrf_exempt` en `borrar_cuenta` (cambia estado) — ALTA — chequeo 14 — `pedidos/views.py`.
- **D09** Open redirect en `salir`: `redirect(request.GET.get("next"))` — MEDIA — chequeo X3 — `pedidos/views.py:31` (semgrep redirect-abierto-py).
- **D10** SSRF en `vista_previa`: `requests.get(request.GET["url"])` — ALTA — chequeo X1 — `pedidos/views.py`.
- **D11** Ejecución por `yaml.load(Loader=yaml.Loader)` en `importar` — CRÍTICA — chequeo X2 — `pedidos/views.py:42`.
- **D12** `pickle.loads` sobre dato del usuario en `carrito` (RCE) — CRÍTICA — chequeo X2 — `pedidos/views.py:47`.
- **D13** XSS almacenado con `mark_safe` y la dirección del usuario en `perfil` — CRÍTICA — chequeo 8 — `pedidos/views.py:51`.
- **D14** Webhook de pago sin verificar firma: `webhook_pago` marca `pagado=True` con cualquier POST — CRÍTICA — chequeo X10 — `pedidos/views.py`.
- **D15** Subida con `file.name` del cliente (path traversal), sin tipo real ni tamaño — CRÍTICA — chequeo 13 — `pedidos/views.py`.
- **D16** Contraseñas con `MD5PasswordHasher` como hasher principal — ALTA — chequeo 5 — `tienda/settings.py`.
- **D17** Sin `SecurityMiddleware` ni `SECURE_*` ni headers de seguridad — MEDIA — chequeo 17 — `tienda/settings.py`.
- **D18** `CORS_ALLOW_ALL_ORIGINS = True` con `CORS_ALLOW_CREDENTIALS = True` — ALTA — chequeo 15 — `tienda/settings.py`.
- **D19** Dependencias con CVE: Django 3.2.0, djangorestframework 3.11.0, requests 2.19.0, PyYAML 5.3; sin lockfile — ALTA — chequeo 20 — `requirements.txt`.
- **D20** Sin throttling de DRF (rate limiting) en ningún endpoint — ALTA — chequeo 11 — `tienda/settings.py`.

## Preguntas para ti

- ❓ 16: ¿Detrás de qué proxy/CDN va y fuerza HTTPS?
- ❓ X6: ¿Hay logs de auth/admin fuera del servidor y con qué retención? (hoy no hay ningún `LOGGING`)
- ❓ X12: ¿Hay respaldo de la base fuera del servidor, inmutable y probado?

## Lo que se revisó y se descartó

- `mis_pedidos`: `get_object_or_404(Pedido, pk=pk, usuario=request.user)` filtra por dueño — correcto.
- `inicio`: `redirect("inicio_view")` por nombre de ruta, no por dato del usuario — correcto.

## Cómo se hizo

Escáneres: gitleaks 8.21.2, semgrep 1.187.0 (solo reglas de la suite), pip-audit 2.10.1 (87 vulnerabilidades en 4 paquetes).
Agentes: infra-secretos, acceso, entradas. Sin pentest (modo auditoría, sin URL).
