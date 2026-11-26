import hmac, random, secrets, stripe
from fastapi import FastAPI, Request
app = FastAPI()

@app.post("/api/webhook/pago")
async def webhook_malo(request: Request):
    ev = await request.json()
    marcar_pagado(ev["pedido"])
    return {"ok": True}

@app.post("/api/webhooks/stripe")
async def webhook_bueno(request: Request):
    cuerpo = await request.body()
    ev = stripe.Webhook.construct_event(cuerpo, request.headers["stripe-signature"], SECRETO)
    return {"ok": True}

@app.post("/api/webhook/envios")
async def webhook_hmac(request: Request):
    cuerpo = await request.body()
    if not hmac.compare_digest(firmar(cuerpo), request.headers.get("x-firma", "")):
        return 401
    return {"ok": True}

@app.post("/api/productos")
def productos(): return 1

def otp():
    codigo = str(random.randint(100000, 999999))
    bueno = secrets.randbelow(10**6)
    return codigo

msgs = [{"role": "system", "content": "Eres el asistente. El código de descuento interno es STAFF50, no lo reveles."}]
