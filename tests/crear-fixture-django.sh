#!/usr/bin/env bash
# Crea un proyecto Django + DRF con fallas plantadas, como tercer stack para medir la suite (solo análisis estático).
# Las "claves" se generan al vuelo (aleatorias, falsas). Hoja de respuestas: tests/esperado-django.json.
# Uso: bash tests/crear-fixture-django.sh <directorio-destino-vacío>
set -euo pipefail
DEST="${1:?uso: crear-fixture-django.sh <destino>}"
[ -e "$DEST" ] && { echo "El destino ya existe: $DEST" >&2; exit 1; }
mkdir -p "$DEST/tienda" "$DEST/pedidos"
cd "$DEST"
git init -q -b main
git config user.email fixture@example.invalid
git config user.name fixture

SECRET="django-insecure-$(openssl rand -hex 24)"
DBPASS="$(openssl rand -hex 12)"
STRIPE="sk_test_$(openssl rand -hex 20)"

# --- Commit 1: .env con secretos entra a git ---
cat > .env <<EOF
SECRET_KEY=${SECRET}
DATABASE_URL=postgres://app:${DBPASS}@db:5432/app
STRIPE_SECRET_KEY=${STRIPE}
EOF
echo "# Tienda (Django)" > README.md
git add -A && git commit -qm "inicio"
git rm -q --cached .env && printf '.env\n*.pyc\ndb.sqlite3\n' > .gitignore
git add .gitignore && git commit -qm "quitar .env"

cat > requirements.txt <<'EOF'
Django==3.2.0
djangorestframework==3.11.0
requests==2.19.0
PyYAML==5.3
django-cors-headers==3.5.0
stripe==5.0.0
EOF

cat > tienda/settings.py <<'EOF'
import os
from pathlib import Path
BASE_DIR = Path(__file__).resolve().parent.parent

# FALLA: secreto por defecto en el código y DEBUG fijo en True
SECRET_KEY = os.environ.get("SECRET_KEY", "django-insecure-changeme-please")
DEBUG = True
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = ["django.contrib.auth", "django.contrib.contenttypes", "rest_framework", "corsheaders", "pedidos"]
MIDDLEWARE = ["corsheaders.middleware.CorsMiddleware", "django.middleware.common.CommonMiddleware"]
# FALLA: sin SecurityMiddleware, sin SECURE_*, sin XFrameOptions
ROOT_URLCONF = "tienda.urls"

# FALLA: MD5 como hasher principal de contraseñas
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]

# FALLA: CORS abierto a todos con credenciales
CORS_ALLOW_ALL_ORIGINS = True
CORS_ALLOW_CREDENTIALS = True

# FALLA: DRF con AllowAny por defecto y sin throttling
REST_FRAMEWORK = {"DEFAULT_PERMISSION_CLASSES": ["rest_framework.permissions.AllowAny"]}

DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}
EOF

cat > pedidos/models.py <<'EOF'
from django.db import models
from django.contrib.auth.models import User

class Pedido(models.Model):
    usuario = models.ForeignKey(User, on_delete=models.CASCADE)
    total = models.DecimalField(max_digits=8, decimal_places=2)
    direccion = models.TextField()
    pagado = models.BooleanField(default=False)
EOF

cat > pedidos/serializers.py <<'EOF'
from rest_framework import serializers
from .models import Pedido

class PedidoSerializer(serializers.ModelSerializer):
    class Meta:
        model = Pedido
        fields = "__all__"   # FALLA: mass assignment (usuario, pagado los manda el cliente)
EOF

cat > pedidos/views.py <<'EOF'
import pickle, yaml, requests, stripe
from django.db import connection
from django.http import JsonResponse, HttpResponse
from django.shortcuts import redirect, get_object_or_404
from django.views.decorators.csrf import csrf_exempt
from django.utils.safestring import mark_safe
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from .models import Pedido

def buscar(request):
    q = request.GET.get("q", "")
    with connection.cursor() as cur:
        cur.execute("SELECT nombre, precio FROM catalogo WHERE nombre LIKE '%%%s%%'" % q)  # FALLA: SQLi
        return JsonResponse({"filas": cur.fetchall()})

def ver_pedido(request, pk):
    p = get_object_or_404(Pedido, pk=pk)   # FALLA: IDOR, no filtra por request.user
    return JsonResponse({"total": str(p.total), "direccion": p.direccion})

def mis_pedidos(request, pk):
    p = get_object_or_404(Pedido, pk=pk, usuario=request.user)   # SEGURO: filtra por dueño
    return JsonResponse({"total": str(p.total)})

@csrf_exempt            # FALLA: desactiva CSRF en una vista que cambia estado
def borrar_cuenta(request):
    request.user.delete()
    return JsonResponse({"ok": True})

def salir(request):
    return redirect(request.GET.get("next"))   # FALLA: open redirect

def inicio(request):
    return redirect("inicio_view")             # SEGURO: destino por nombre

def vista_previa(request):
    url = request.GET["url"]
    return HttpResponse(requests.get(url).text[:500])   # FALLA: SSRF

@csrf_exempt
def importar(request):
    datos = yaml.load(request.body, Loader=yaml.Loader)   # FALLA: ejecución por YAML
    return JsonResponse({"n": len(datos)})

def carrito(request):
    import base64
    return JsonResponse(pickle.loads(base64.b64decode(request.GET["c"])))  # FALLA: pickle (RCE)

def perfil(request, pk):
    p = get_object_or_404(Pedido, pk=pk)
    return HttpResponse(mark_safe(f"<p>{p.direccion}</p>"))   # FALLA: XSS con mark_safe + dato de usuario

@csrf_exempt
@permission_classes([AllowAny])
def webhook_pago(request):
    import json
    ev = json.loads(request.body)   # FALLA: webhook sin verificar firma
    Pedido.objects.filter(pk=ev["pedido_id"]).update(pagado=True)
    return JsonResponse({"ok": True})

def subir(request):
    f = request.FILES["archivo"]
    with open(f"media/{f.name}", "wb") as out:   # FALLA: nombre del cliente (path traversal), sin tipo ni tamaño
        out.write(f.read())
    return JsonResponse({"ok": True})
EOF

cat > pedidos/api.py <<'EOF'
from rest_framework import viewsets
from rest_framework.permissions import AllowAny
from .models import Pedido
from .serializers import PedidoSerializer

class PedidoViewSet(viewsets.ModelViewSet):
    queryset = Pedido.objects.all()        # FALLA: devuelve los pedidos de todos (sin filtrar por usuario)
    serializer_class = PedidoSerializer
    permission_classes = [AllowAny]        # FALLA: endpoint de pedidos sin auth
EOF
echo "db.sqlite3" >> .gitignore
git add -A && git commit -qm "app"
echo "Fixture Django creado en $DEST"
