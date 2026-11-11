"""
Endurecimiento listo para FastAPI (security-suite). Copia este archivo a tu app y llama a `endurecer(app)`.

Dependencias: pip install argon2-cffi slowapi pydantic-settings

Cubre los chequeos 2, 5, 11, 15, 17, 18 y 19 de SecurityChecks.md.
"""
from __future__ import annotations

import logging
import secrets

from argon2 import PasswordHasher
from argon2.exceptions import VerificationError, InvalidHashError
from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

log = logging.getLogger("seguridad")


# --- 2 / 19: configuración que falla si falta un secreto, sin debug por defecto -------------------
class Ajustes(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    secret_key: SecretStr                      # sin valor por defecto: la app NO arranca sin él
    entorno: str = "produccion"                # "local" | "staging" | "produccion"
    origenes_cors: list[str] = []              # p. ej. ["https://midominio.com"]
    detras_de_cloudflare: bool = False         # True solo si el origen SOLO es accesible vía Cloudflare (tunnel)

    @property
    def produccion(self) -> bool:
        return self.entorno == "produccion"


ajustes = Ajustes()  # type: ignore[call-arg]


def crear_app(**kwargs) -> FastAPI:
    """FastAPI sin /docs, /redoc ni /openapi.json en producción."""
    if ajustes.produccion:
        kwargs.update(docs_url=None, redoc_url=None, openapi_url=None)
    return FastAPI(debug=False, **kwargs)


# --- 5: contraseñas con argon2id -------------------------------------------------------------------
_ph = PasswordHasher()


def hashear_password(password: str) -> str:
    return _ph.hash(password)


def verificar_password(hash_guardado: str, password: str) -> bool:
    try:
        return _ph.verify(hash_guardado, password)
    except (VerificationError, InvalidHashError):
        return False


def necesita_rehash(hash_guardado: str) -> bool:
    return _ph.check_needs_rehash(hash_guardado)


def nuevo_token_sesion() -> str:
    return secrets.token_urlsafe(32)


# --- 11: rate limiting con la IP real -------------------------------------------------------------
def ip_real(request: Request) -> str:
    # CF-Connecting-IP solo es confiable si NADIE puede llegar al origen sin pasar por Cloudflare.
    if ajustes.detras_de_cloudflare:
        ip = request.headers.get("cf-connecting-ip")
        if ip:
            return ip
    return request.client.host if request.client else "desconocida"


limiter = Limiter(key_func=ip_real, default_limits=["120/minute"])
# Uso en endpoints sensibles (el endpoint debe recibir `request: Request`):
#   @app.post("/login")
#   @limiter.limit("5/minute")
#   def login(request: Request, ...): ...


# --- 18: cookie de sesión segura -------------------------------------------------------------------
def poner_cookie_sesion(response: Response, token: str, max_age: int = 60 * 60 * 24 * 7) -> None:
    response.set_cookie(
        "__Host-sesion" if ajustes.produccion else "sesion",
        token,
        max_age=max_age,
        httponly=True,
        secure=ajustes.produccion,
        samesite="lax",
        path="/",
    )


# --- 17: headers de seguridad ---------------------------------------------------------------------
HEADERS = {
    "X-Content-Type-Options": "nosniff",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=(), payment=()",
    "X-Frame-Options": "DENY",
    # Ajusta la CSP a tu front; empieza estricta y abre solo lo necesario.
    "Content-Security-Policy": (
        "default-src 'self'; img-src 'self' data: https:; style-src 'self' 'unsafe-inline'; "
        "script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'"
    ),
}


def endurecer(app: FastAPI) -> None:
    """Aplica headers, CORS explícito, rate limiting y errores sin detalles internos."""

    @app.middleware("http")
    async def _headers(request: Request, call_next):
        resp = await call_next(request)
        for k, v in HEADERS.items():
            resp.headers.setdefault(k, v)
        if ajustes.produccion:
            resp.headers.setdefault("Strict-Transport-Security", "max-age=31536000; includeSubDomains")
        if "server" in resp.headers:
            del resp.headers["server"]
        return resp

    # 15: nunca "*" con credenciales
    if ajustes.origenes_cors:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=ajustes.origenes_cors,
            allow_credentials=True,
            allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
            allow_headers=["Content-Type", "Authorization", "X-CSRF-Token"],
        )

    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    # 19: el cliente nunca ve tracebacks
    @app.exception_handler(Exception)
    async def _error_generico(request: Request, exc: Exception):
        log.exception("Error no controlado en %s %s", request.method, request.url.path)
        return JSONResponse({"error": "Error interno"}, status_code=500)


# --- 6: patrón anti-IDOR (ejemplo con SQLAlchemy) ---------------------------------------------------
# def obtener_pedido(db, usuario, pedido_id):
#     pedido = db.scalar(select(Pedido).where(Pedido.id == pedido_id, Pedido.usuario_id == usuario.id))
#     if pedido is None:
#         raise HTTPException(404)   # 404, no 403: no confirmes que el recurso existe
#     return pedido

# --- 7: modelos de entrada estrictos --------------------------------------------------------------
# class RegistroIn(BaseModel):
#     model_config = ConfigDict(extra="forbid")       # rechaza "rol", "is_admin", etc.
#     email: EmailStr
#     password: str = Field(min_length=10, max_length=128)
