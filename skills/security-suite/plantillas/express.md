# Plantillas: Express (Node.js)

Endurecimiento base y arreglos para los chequeos más comunes. Paquetes: `helmet`, `express-rate-limit`, `zod`,
`cookie-parser`, `stripe`.

```js
// app.js
import express from "express";
import helmet from "helmet";
import rateLimit from "express-rate-limit";
import cookieParser from "cookie-parser";
import Stripe from "stripe";
import crypto from "crypto";
import { z } from "zod";

const app = express();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY);
if (!process.env.SESSION_SECRET || !process.env.STRIPE_WEBHOOK_SECRET) throw new Error("Faltan secretos"); // 2

app.disable("x-powered-by");                                    // 17
app.set("trust proxy", 1);                                      // 11: IP real detrás de UN proxy (Cloudflare/Render/Fly)
app.use(helmet({                                                // 17: CSP, HSTS, nosniff, frame-ancestors…
  contentSecurityPolicy: { directives: { "default-src": ["'self'"], "img-src": ["'self'", "data:"], "frame-ancestors": ["'none'"] } },
  strictTransportSecurity: { maxAge: 63072000, includeSubDomains: true },
}));

// X10: el webhook va ANTES de express.json(), con el cuerpo crudo
app.post("/webhooks/stripe", express.raw({ type: "application/json" }), async (req, res) => {
  let evento;
  try {
    evento = stripe.webhooks.constructEvent(req.body, req.headers["stripe-signature"], process.env.STRIPE_WEBHOOK_SECRET);
  } catch {
    return res.status(400).send("firma inválida");
  }
  if (await yaProcesado(evento.id)) return res.json({ recibido: true });   // idempotencia (tabla con id UNIQUE)
  // … cruzar monto y pedido con la base antes de marcar como pagado
  res.json({ recibido: true });
});

app.use(express.json({ limit: "100kb" }));                      // 7: tamaño máximo
app.use(cookieParser());

// 15: CORS con lista explícita (si hace falta)
const ORIGENES = new Set((process.env.ORIGENES ?? "").split(",").filter(Boolean));
app.use((req, res, next) => {
  const o = req.headers.origin;
  if (o && ORIGENES.has(o)) { res.setHeader("Access-Control-Allow-Origin", o); res.setHeader("Access-Control-Allow-Credentials", "true"); res.setHeader("Vary", "Origin"); }
  next();
});

// 11: límites
const limiteLogin = rateLimit({ windowMs: 15 * 60_000, limit: 10, standardHeaders: "draft-7", legacyHeaders: false });
const limiteGeneral = rateLimit({ windowMs: 60_000, limit: 120 });
app.use("/api", limiteGeneral);
app.use(["/api/login", "/api/registro", "/api/recuperar", "/api/otp"], limiteLogin);

// 18: cookie de sesión
function ponerSesion(res, token) {
  res.cookie("__Host-sesion", token, { httpOnly: true, secure: true, sameSite: "lax", path: "/", maxAge: 7 * 86400_000 });
}

// 14: CSRF por Origin en métodos que cambian estado (con cookies SameSite=Lax como primera capa)
app.use((req, res, next) => {
  if (["GET", "HEAD", "OPTIONS"].includes(req.method) || req.path.startsWith("/webhooks/")) return next();
  const o = req.headers.origin;
  if (!o || !ORIGENES.has(o) && o !== `${req.protocol}://${req.get("host")}`) return res.status(403).json({ error: "Origen no permitido" });
  next();
});

// 7: validación con esquema estricto (sin mass assignment)
const Registro = z.object({ email: z.string().email().max(254), password: z.string().min(12).max(128) }).strict();
app.post("/api/registro", (req, res) => {
  const r = Registro.safeParse(req.body);
  if (!r.success) return res.status(400).json({ error: "Datos inválidos" });
  // rol SIEMPRE "cliente" aquí; los admin se crean a mano
});

// 4, 6: auth + rol + dueño
const requiereSesion = (req, res, next) => (req.usuario = leerSesion(req)) ? next() : res.status(401).json({ error: "Inicia sesión" });
const requiereAdmin = (req, res, next) => req.usuario?.rol === "admin" ? next() : res.status(403).json({ error: "Sin permiso" });
app.get("/api/pedidos/:id", requiereSesion, async (req, res) => {
  const p = await db.pedido.findFirst({ where: { id: req.params.id, usuarioId: req.usuario.id } });  // dueño en el where
  return p ? res.json(p) : res.status(404).json({ error: "No encontrado" });
});
app.use("/api/admin", requiereSesion, requiereAdmin);

// X3: redirecciones solo internas
app.get("/salir", (req, res) => {
  const d = String(req.query.next ?? "/");
  res.redirect(d.startsWith("/") && !d.startsWith("//") && !d.startsWith("/\\") ? d : "/");
});

// 11: códigos cortos
const codigo = () => String(crypto.randomInt(0, 1_000_000)).padStart(6, "0");   // nunca Math.random
// guardar hash + intentos + expiración; invalidar al 5.º fallo (ver plantillas/nextjs-supabase.md, sección 7)

// 19: errores sin detalles
app.use((err, req, res, _next) => { console.error(err); res.status(500).json({ error: "Error interno" }); });
```
