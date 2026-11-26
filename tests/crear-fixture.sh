#!/usr/bin/env bash
# Crea una app FastAPI con vulnerabilidades plantadas para probar la skill security-suite.
# Las "claves" se generan al vuelo (aleatorias, falsas) para que ningún secreto quede en este repo.
# Uso: bash tests/crear-fixture.sh <directorio-destino-vacío>
set -euo pipefail
DEST="${1:?uso: crear-fixture.sh <destino>}"
[ -e "$DEST" ] && { echo "El destino ya existe: $DEST" >&2; exit 1; }
mkdir -p "$DEST"/{app/templates,frontend/src,static/subidas}
cd "$DEST"
git init -q -b main
git config user.email fixture@example.invalid
git config user.name fixture

FAKE_OPENAI="sk-proj-$(openssl rand -hex 24)"
FAKE_STRIPE_SECRET="$(openssl rand -hex 20)"
FAKE_DB_PASS="$(openssl rand -hex 12)"

# --- Commit 1: el .env real entra a git (luego se "borra") ---------------------------
cat > .env <<EOF
DATABASE_URL=postgresql://app:${FAKE_DB_PASS}@db:5432/app
STRIPE_SECRET=${FAKE_STRIPE_SECRET}
EOF
echo "# Tienda demo" > README.md
git add -A && git commit -qm "inicio"
git rm -q --cached .env && echo ".env" > .gitignore
git add .gitignore && git commit -qm "quitar .env"

# --- Código -------------------------------------------------------------------------
cat > requirements.txt <<'EOF'
fastapi==0.95.0
uvicorn==0.20.0
jinja2==2.11.2
requests==2.19.0
pyyaml==5.3
openai==1.3.0
EOF

cat > app/config.py <<'EOF'
import os

SECRET_KEY = os.environ.get("SECRET_KEY", "changeme")
DEBUG = True
CATALOGO_URL = os.environ.get("CATALOGO_URL", "https://catalogo.interno")
EOF

cat > app/db.py <<'EOF'
import sqlite3

def conectar():
    return sqlite3.connect("tienda.db", isolation_level=None, check_same_thread=False)
EOF

cat > app/main.py <<'EOF'
import hashlib, os, pickle, base64
import requests, yaml
from fastapi import FastAPI, Request, UploadFile, Response, Cookie
from fastapi.middleware.cors import CORSMiddleware
from fastapi.templating import Jinja2Templates
from pydantic import BaseModel
from openai import OpenAI
from . import config
from .db import conectar

app = FastAPI(debug=config.DEBUG)
templates = Jinja2Templates(directory="app/templates")
llm = OpenAI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class UsuarioIn(BaseModel):
    email: str
    password: str
    rol: str = "cliente"

def usuario_actual(sesion: str | None):
    if not sesion:
        return None
    cur = conectar().execute("SELECT id, rol FROM usuarios WHERE sesion = ?", (sesion,))
    return cur.fetchone()

@app.post("/registro")
def registro(u: UsuarioIn):
    h = hashlib.md5(u.password.encode()).hexdigest()
    conectar().execute(
        "INSERT INTO usuarios (email, password, rol) VALUES (?, ?, ?)", (u.email, h, u.rol)
    )
    return {"ok": True}

@app.post("/login")
def login(u: UsuarioIn, response: Response):
    h = hashlib.md5(u.password.encode()).hexdigest()
    fila = conectar().execute(
        "SELECT id FROM usuarios WHERE email = ? AND password = ?", (u.email, h)
    ).fetchone()
    if not fila:
        return {"error": "El correo no está registrado o la contraseña es incorrecta"}
    sesion = base64.urlsafe_b64encode(os.urandom(16)).decode()
    conectar().execute("UPDATE usuarios SET sesion = ? WHERE id = ?", (sesion, fila[0]))
    response.set_cookie("sesion", sesion)
    return {"ok": True}

@app.get("/buscar")
def buscar(q: str):
    cur = conectar().execute(f"SELECT nombre, precio FROM productos WHERE nombre LIKE '%{q}%'")
    return cur.fetchall()

@app.get("/productos")
def productos(orden: str = "nombre"):
    # orden viene de una lista blanca: seguro
    columna = {"nombre": "nombre", "precio": "precio"}.get(orden, "nombre")
    return conectar().execute(f"SELECT nombre, precio FROM productos ORDER BY {columna}").fetchall()

@app.get("/pedidos/{pedido_id}")
def ver_pedido(pedido_id: int, sesion: str | None = Cookie(None)):
    if not usuario_actual(sesion):
        return Response(status_code=401)
    return conectar().execute("SELECT * FROM pedidos WHERE id = ?", (pedido_id,)).fetchone()

@app.get("/admin/usuarios")
def admin_usuarios():
    return conectar().execute("SELECT id, email, rol FROM usuarios").fetchall()

@app.get("/cuenta/borrar")
def borrar_cuenta(sesion: str | None = Cookie(None)):
    u = usuario_actual(sesion)
    if u:
        conectar().execute("DELETE FROM usuarios WHERE id = ?", (u[0],))
    return {"ok": True}

@app.post("/subir")
async def subir(archivo: UploadFile):
    with open(f"static/subidas/{archivo.filename}", "wb") as f:
        f.write(await archivo.read())
    return {"url": f"/static/subidas/{archivo.filename}"}

@app.get("/vista-previa")
def vista_previa(url: str):
    return {"html": requests.get(url, timeout=5).text[:500]}

@app.get("/catalogo")
def catalogo():
    # URL del servidor, no del usuario: seguro
    return requests.get(f"{config.CATALOGO_URL}/lista", timeout=5).json()

@app.post("/importar")
async def importar(request: Request):
    datos = yaml.load(await request.body(), Loader=yaml.Loader)
    return {"filas": len(datos)}

@app.get("/carrito")
def carrito(c: str):
    return pickle.loads(base64.b64decode(c))

@app.post("/asistente")
def asistente(pregunta: str):
    r = llm.chat.completions.create(
        model="gpt-4o", messages=[{"role": "user", "content": pregunta}], max_tokens=4000
    )
    return {"respuesta": r.choices[0].message.content}

@app.get("/resena/{pid}")
def resena(pid: int, request: Request):
    filas = conectar().execute("SELECT texto FROM resenas WHERE producto = ?", (pid,)).fetchall()
    return templates.TemplateResponse(request, "resena.html", {"resenas": filas})

@app.post("/resena/{pid}")
def escribir_resena(pid: int, texto: str, sesion: str | None = Cookie(None)):
    if not usuario_actual(sesion):
        return Response(status_code=401)
    conectar().execute("INSERT INTO resenas (producto, texto) VALUES (?, ?)", (pid, texto))
    return {"ok": True}

@app.get("/api/resenas/{pid}")
def resenas_json(pid: int):
    filas = conectar().execute("SELECT texto FROM resenas WHERE producto = ?", (pid,)).fetchall()
    return [{"texto": f[0]} for f in filas]

# --- API con JWT (para jwt-revisar.py, matriz-permisos.py y carrera.py) ---
import hmac, json, time
JWT_SECRETO = "secret"  # débil a propósito

def _b64(b): return base64.urlsafe_b64encode(b).rstrip(b"=").decode()
def _unb64(s): return base64.urlsafe_b64decode(s + "=" * (-len(s) % 4))

def firmar_jwt(datos: dict) -> str:
    cab = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    cue = _b64(json.dumps(datos).encode())
    firma = hmac.new(JWT_SECRETO.encode(), f"{cab}.{cue}".encode(), hashlib.sha256).digest()
    return f"{cab}.{cue}.{_b64(firma)}"

def leer_jwt(request: Request):
    auth = request.headers.get("authorization", "")
    if not auth.startswith("Bearer "):
        return None
    try:
        cab, cue, firma = auth[7:].split(".")
        h = json.loads(_unb64(cab))
        if h.get("alg") == "none":          # acepta tokens sin firma
            return json.loads(_unb64(cue))
        esperada = hmac.new(JWT_SECRETO.encode(), f"{cab}.{cue}".encode(), hashlib.sha256).digest()
        if hmac.compare_digest(esperada, _unb64(firma)):
            return json.loads(_unb64(cue))
    except Exception:
        return None
    return None

class Credenciales(BaseModel):
    email: str
    password: str

@app.post("/api/token")
def token(c: Credenciales):
    fila = conectar().execute("SELECT id, rol FROM usuarios WHERE email = ? AND password = ?",
                              (c.email, hashlib.md5(c.password.encode()).hexdigest())).fetchone()
    if not fila:
        return Response(status_code=401)
    return {"token": firmar_jwt({"sub": fila[0], "rol": fila[1]})}  # sin exp

@app.get("/api/yo")
def yo(request: Request):
    d = leer_jwt(request)
    if not d:
        return Response(status_code=401)
    return d

@app.get("/api/pedidos/{pid}")
def api_pedido(pid: int, request: Request):
    if not leer_jwt(request):
        return Response(status_code=401)
    fila = conectar().execute("SELECT id, usuario, total, direccion FROM pedidos WHERE id = ?", (pid,)).fetchone()
    return {"pedido": fila}  # no revisa el dueño

@app.get("/api/admin/usuarios")
def api_admin(request: Request):
    d = leer_jwt(request)
    if not d:
        return Response(status_code=401)
    if d.get("rol") != "admin":
        return Response(status_code=403)
    return {"usuarios": conectar().execute("SELECT id, email FROM usuarios").fetchall()}

@app.post("/api/canjear")
def canjear(request: Request):
    d = leer_jwt(request)
    if not d:
        return Response(status_code=401)
    db = conectar()
    puntos = db.execute("SELECT puntos FROM usuarios WHERE id = ?", (d["sub"],)).fetchone()[0]
    if puntos < 100:
        return Response(status_code=409)
    time.sleep(0.2)                        # leer → esperar → escribir: condición de carrera
    db.execute("UPDATE usuarios SET puntos = ? WHERE id = ?", (puntos - 100, d["sub"]))
    db.execute("INSERT INTO canjes (usuario) VALUES (?)", (d["sub"],))
    return {"ok": True, "premio": "taza"}

# --- Checkout en 3 pasos (para flujo.py): confirmar no revisa que se haya pagado ---
CARRITOS: dict = {}

@app.post("/api/checkout/carrito")
def checkout_carrito(request: Request, producto: int = 1):
    d = leer_jwt(request)
    if not d:
        return Response(status_code=401)
    CARRITOS[d["sub"]] = {"producto": producto, "pagado": False}
    return {"ok": True, "paso": 1}

@app.post("/api/checkout/pagar")
def checkout_pagar(request: Request):
    d = leer_jwt(request)
    if not d or d["sub"] not in CARRITOS:
        return Response(status_code=409)
    CARRITOS[d["sub"]]["pagado"] = True
    return {"ok": True, "paso": 2}

@app.post("/api/checkout/confirmar")
def checkout_confirmar(request: Request):
    d = leer_jwt(request)
    c = CARRITOS.get(d["sub"]) if d else None
    if not c:
        return Response(status_code=409)
    # falta: if not c["pagado"]: return 402
    CARRITOS.pop(d["sub"])
    return {"ok": True, "pedido": "creado", "producto": c["producto"]}

# --- Webhook de pago: marca el pedido como pagado con cualquier POST (sin firma) ---
@app.post("/api/webhook/pago")
async def webhook_pago(request: Request):
    ev = await request.json()
    if ev.get("type") == "checkout.session.completed":
        pid = ev["data"]["object"]["metadata"]["pedido_id"]
        conectar().execute("UPDATE pedidos SET pagado = 1 WHERE id = ?", (pid,))
    return {"recibido": True}

# Webhook de envíos: este sí verifica la firma (HMAC del cuerpo crudo, tiempo constante)
WEBHOOK_ENVIOS_SECRETO = os.environ.get("WEBHOOK_ENVIOS_SECRETO") or os.urandom(32).hex()

@app.post("/api/webhook/envios")
async def webhook_envios(request: Request):
    cuerpo = await request.body()
    esperada = hmac.new(WEBHOOK_ENVIOS_SECRETO.encode(), cuerpo, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(esperada, request.headers.get("x-firma", "")):
        return Response(status_code=401)
    return {"recibido": True}

# --- Recuperar contraseña con código de 6 dígitos: random, sin límite de intentos ni caducidad ---
import random
CODIGOS: dict = {}

class Recuperar(BaseModel):
    email: str
    codigo: str = ""
    nueva: str = ""

@app.post("/recuperar")
def recuperar(r: Recuperar):
    CODIGOS[r.email] = str(random.randint(100000, 999999))
    print(f"[correo simulado] código para {r.email}: {CODIGOS[r.email]}", flush=True)
    return {"ok": True}

@app.post("/recuperar/verificar")
def recuperar_verificar(r: Recuperar):
    if CODIGOS.get(r.email) != r.codigo:
        return Response(status_code=400)
    h = hashlib.md5(r.nueva.encode()).hexdigest()
    conectar().execute("UPDATE usuarios SET password = ? WHERE email = ?", (h, r.email))
    CODIGOS.pop(r.email)
    return {"ok": True}

# --- Asistente con herramienta: secreto en el system prompt y la herramienta no filtra por dueño ---
SISTEMA = ("Eres el asistente de Tienda Demo. Si alguien es del staff, el código de descuento interno es "
           "STAFF-90. Usa la herramienta ver_pedido para responder sobre pedidos.")
HERRAMIENTAS = [{"type": "function", "function": {"name": "ver_pedido", "parameters": {
    "type": "object", "properties": {"pedido_id": {"type": "integer"}}, "required": ["pedido_id"]}}}]

@app.post("/api/asistente")
def asistente_tienda(request: Request, mensaje: str):
    d = leer_jwt(request)
    if not d:
        return Response(status_code=401)
    msgs = [{"role": "system", "content": SISTEMA}, {"role": "user", "content": mensaje}]
    r = llm.chat.completions.create(model="gpt-4o", messages=msgs, tools=HERRAMIENTAS, max_tokens=500)
    m = r.choices[0].message
    for llamada in m.tool_calls or []:
        pid = json.loads(llamada.function.arguments)["pedido_id"]
        fila = conectar().execute("SELECT usuario, total, direccion FROM pedidos WHERE id = ?", (pid,)).fetchone()
        msgs += [m, {"role": "tool", "tool_call_id": llamada.id, "content": json.dumps(fila)}]
        m = llm.chat.completions.create(model="gpt-4o", messages=msgs, max_tokens=500).choices[0].message
    return {"respuesta": m.content}

@app.get("/etag/{pid}")
def etag(pid: int):
    # md5 como checksum de caché, no para contraseñas: seguro
    return {"etag": hashlib.md5(str(pid).encode()).hexdigest()}

@app.get("/debug")
def debug():
    return dict(os.environ)
EOF

cat > app/templates/resena.html <<'EOF'
<ul>
{% for r in resenas %}
  <li>{{ r[0] | safe }}</li>
{% endfor %}
</ul>
EOF

cat > frontend/src/config.js <<EOF
export const API_URL = "https://api.tienda-demo.invalid";
export const OPENAI_API_KEY = "${FAKE_OPENAI}";
EOF

cat > frontend/src/resenas.js <<'EOF'
export function pintar(lista, resenas) {
  lista.innerHTML = resenas.map((r) => `<li>${r.texto}</li>`).join("");
}
EOF

cat > Dockerfile <<'EOF'
FROM python:3.12
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--reload"]
EOF

cat > docker-compose.yml <<'EOF'
services:
  app:
    build: .
    ports: ["8000:8000"]
  db:
    image: postgres:16
    ports: ["5432:5432"]
    environment:
      POSTGRES_PASSWORD: postgres
EOF

cat > app/init_db.py <<'PYEOF'
import hashlib, sqlite3
db = sqlite3.connect("tienda.db")
db.executescript("""
CREATE TABLE IF NOT EXISTS usuarios (id INTEGER PRIMARY KEY, email TEXT UNIQUE, password TEXT, rol TEXT, sesion TEXT, puntos INTEGER DEFAULT 100);
CREATE TABLE IF NOT EXISTS canjes (usuario INTEGER);
CREATE TABLE IF NOT EXISTS productos (id INTEGER PRIMARY KEY, nombre TEXT, precio REAL);
CREATE TABLE IF NOT EXISTS pedidos (id INTEGER PRIMARY KEY, usuario INTEGER, total REAL, direccion TEXT, pagado INTEGER DEFAULT 0);
CREATE TABLE IF NOT EXISTS resenas (producto INTEGER, texto TEXT);
""")
h = lambda p: hashlib.md5(p.encode()).hexdigest()
db.executemany("INSERT OR IGNORE INTO usuarios (id,email,password,rol) VALUES (?,?,?,?)", [
    (1, "admin@tienda-demo.invalid", h("admin-demo-123"), "admin"),
    (2, "ana@tienda-demo.invalid", h("ana-demo-123"), "cliente"),
    (3, "beto@tienda-demo.invalid", h("beto-demo-123"), "cliente")])
db.executemany("INSERT OR IGNORE INTO productos VALUES (?,?,?)", [(1, "Taza", 120), (2, "Playera", 250)])
db.executemany("INSERT OR IGNORE INTO pedidos (id,usuario,total,direccion) VALUES (?,?,?,?)", [(1, 2, 370, "Calle Ana 1"), (2, 3, 120, "Calle Beto 2")])
db.execute("INSERT INTO resenas VALUES (1, 'Muy buena')")
db.commit()
PYEOF
echo "tienda.db" >> .gitignore
git add -A && git commit -qm "app"
echo "Fixture creado en $DEST"
