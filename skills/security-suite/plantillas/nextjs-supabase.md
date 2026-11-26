# Plantillas: Next.js (App Router) + Supabase + Stripe

Arreglos listos para las fallas típicas de una app hecha con IA. Cada bloque dice qué chequeo cierra.
Versiones de referencia: Next.js 14.2.25+ o 15.2.3+ (CVE-2025-29927), `@supabase/ssr`, `stripe` 14+.

## 1. Dos clientes de Supabase, la service_role solo en el servidor (1, 10)

```ts
// lib/supabase/servidor.ts — SOLO en route handlers, server actions y server components
import "server-only";                                   // rompe el build si un componente cliente lo importa
import { createClient } from "@supabase/supabase-js";
import { cookies } from "next/headers";
import { createServerClient } from "@supabase/ssr";

// Cliente del USUARIO: respeta la RLS. Úsalo por defecto.
export function supabaseUsuario() {
  const c = cookies();
  return createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: { getAll: () => c.getAll(), setAll: (l) => l.forEach(({ name, value, options }) => c.set(name, value, options)) },
  });
}

// Cliente ADMIN: salta la RLS. Solo para webhooks y tareas internas, nunca con datos que elige el usuario.
// Nombre SIN prefijo público: SUPABASE_SERVICE_ROLE_KEY (nunca NEXT_PUBLIC_…). Si estuvo pública: rotarla.
export const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY!, {
  auth: { persistSession: false },
});
```

## 2. RLS en todas las tablas (10, 6)

```sql
-- Cada tabla de public: RLS activa + políticas por dueño. Sin política = nadie (salvo service_role).
alter table public.pedidos enable row level security;
create policy "pedidos: ver los míos"   on public.pedidos for select to authenticated using (usuario = auth.uid());
create policy "pedidos: crear los míos" on public.pedidos for insert to authenticated with check (usuario = auth.uid());
-- sin update/delete desde el cliente: el estado "pagado" lo escribe solo el webhook con service_role

-- Roles: en app_metadata (solo el servidor lo escribe), NUNCA en user_metadata (lo edita el usuario)
create policy "reportes: solo admin" on public.reportes for select to authenticated
  using ((auth.jwt() -> 'app_metadata' ->> 'rol') = 'admin');

-- Catálogo público a propósito: solo lectura, y decláralo (--publicas en supabase-rls.py)
create policy "catalogo: lectura publica" on public.productos for select to anon, authenticated using (true);

-- Funciones security definer: search_path fijo y operaciones atómicas
create or replace function public.canjear_cupon(c text) returns int
language sql security definer set search_path = public as $$
  update public.cupones set usos = usos + 1 where codigo = c and usos < max_usos returning descuento;
$$;
revoke execute on function public.canjear_cupon(text) from anon;
```
Verificación: `python3 SKILL/scripts/supabase-rls.py . --publicas productos` debe salir 0.

## 3. `/admin` protegido en el servidor (4)

```ts
// middleware.ts — primera barrera (Next ≥ 14.2.25: antes se podía saltar con x-middleware-subrequest)
import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

export async function middleware(req: NextRequest) {
  const res = NextResponse.next();
  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: { getAll: () => req.cookies.getAll(), setAll: (l) => l.forEach(({ name, value, options }) => res.cookies.set(name, value, options)) },
  });
  const { data: { user } } = await supabase.auth.getUser();          // getUser valida con Supabase; getSession no
  if (!user || user.app_metadata?.rol !== "admin") return NextResponse.redirect(new URL("/", req.url));
  return res;
}
export const config = { matcher: ["/admin/:path*", "/api/admin/:path*"] };
```
El middleware no basta solo: **cada** route handler de admin vuelve a comprobar `getUser()` + rol, y los datos los
filtra la RLS. Un `if` en un componente `"use client"` no protege nada.

## 4. Checkout con el precio del servidor (X4)

```ts
// app/api/checkout/route.ts
import Stripe from "stripe";
import { NextRequest, NextResponse } from "next/server";
import { supabaseUsuario } from "@/lib/supabase/servidor";
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: NextRequest) {
  const supabase = supabaseUsuario();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Inicia sesión" }, { status: 401 });
  const { productoId, cantidad } = await req.json();                       // del cliente: QUÉ quiere, no cuánto cuesta
  const n = Math.min(Math.max(Number.parseInt(cantidad, 10) || 1, 1), 10);
  const { data: p } = await supabase.from("productos").select("id, nombre, precio_centavos").eq("id", productoId).single();
  if (!p) return NextResponse.json({ error: "Producto no encontrado" }, { status: 404 });
  const { data: pedido } = await supabase.from("pedidos")
    .insert({ usuario: user.id, total_centavos: p.precio_centavos * n }).select("id").single();
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{ quantity: n, price_data: { currency: "mxn", unit_amount: p.precio_centavos, product_data: { name: p.nombre } } }],
    metadata: { pedidoId: String(pedido!.id) },
    success_url: `${req.nextUrl.origin}/gracias`, cancel_url: `${req.nextUrl.origin}/carrito`,
  });
  return NextResponse.json({ url: session.url });
}
```

## 5. Webhook de Stripe firmado e idempotente (X10)

```ts
// app/api/webhooks/stripe/route.ts
import Stripe from "stripe";
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase/servidor";
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: NextRequest) {
  const cuerpo = await req.text();                                          // cuerpo CRUDO: req.json() rompe la firma
  let evento: Stripe.Event;
  try {
    evento = stripe.webhooks.constructEvent(cuerpo, req.headers.get("stripe-signature")!, process.env.STRIPE_WEBHOOK_SECRET!);
  } catch {
    return new NextResponse("firma inválida", { status: 400 });
  }
  // idempotencia: tabla eventos_webhook(id text primary key)
  const { error: repetido } = await supabaseAdmin.from("eventos_webhook").insert({ id: evento.id });
  if (repetido) return NextResponse.json({ recibido: true });              // ya procesado
  if (evento.type === "checkout.session.completed") {
    const s = evento.data.object as Stripe.Checkout.Session;
    if (s.payment_status !== "paid") return NextResponse.json({ recibido: true });
    const { data: pedido } = await supabaseAdmin.from("pedidos").select("id, total_centavos").eq("id", s.metadata!.pedidoId).single();
    if (!pedido || pedido.total_centavos !== s.amount_total) {              // cruzar monto con la base
      console.error("webhook: monto no coincide", evento.id);
      return NextResponse.json({ recibido: true });
    }
    await supabaseAdmin.from("pedidos").update({ pagado: true, stripe_session: s.id }).eq("id", pedido.id);
  }
  return NextResponse.json({ recibido: true });
}
```

## 6. Consultas por id con dueño (6)

```ts
// app/api/pedidos/[id]/route.ts — cliente del usuario (RLS) + filtro explícito (defensa en profundidad)
const supabase = supabaseUsuario();
const { data: { user } } = await supabase.auth.getUser();
if (!user) return NextResponse.json({ error: "Inicia sesión" }, { status: 401 });
const { data } = await supabase.from("pedidos").select("*").eq("id", params.id).eq("usuario", user.id).maybeSingle();
if (!data) return NextResponse.json({ error: "No encontrado" }, { status: 404 });    // 404, no 403: no confirma que existe
```

## 7. Códigos de verificación (11)

```ts
import { randomInt, createHash, timingSafeEqual } from "crypto";
const hash = (c: string) => createHash("sha256").update(c).digest();
// generar: tabla codigos(email, hash, intentos int default 0, expira timestamptz)
const codigo = String(randomInt(0, 1_000_000)).padStart(6, "0");
await supabaseAdmin.from("codigos").upsert({ email, hash: hash(codigo).toString("hex"), intentos: 0,
  expira: new Date(Date.now() + 10 * 60_000).toISOString() });
// verificar
const { data: c } = await supabaseAdmin.from("codigos").select("*").eq("email", email).maybeSingle();
if (!c || new Date(c.expira) < new Date() || c.intentos >= 5) return NextResponse.json({ ok: false }, { status: 400 });
await supabaseAdmin.from("codigos").update({ intentos: c.intentos + 1 }).eq("email", email);
const ok = timingSafeEqual(hash(String(codigo)), Buffer.from(c.hash, "hex"));
if (ok) await supabaseAdmin.from("codigos").delete().eq("email", email);   // de un solo uso
```
Mejor aún: usar el OTP de Supabase Auth (`signInWithOtp`/`verifyOtp`), que ya trae límites.

## 8. Chatbot (X11, 8, 12)

```ts
// Servidor: nada secreto en el prompt; sesión, rate limit y max_tokens
const SISTEMA = "Eres el asistente de la tienda. Responde solo sobre productos y pedidos del usuario.";
// herramienta ver_pedido: SIEMPRE con el cliente del usuario (RLS), nunca con supabaseAdmin
// Cliente: la respuesta es texto
<div className="whitespace-pre-wrap">{respuesta}</div>
// Si necesitas markdown: react-markdown sin rehype-raw y sin imágenes remotas
<ReactMarkdown components={{ img: () => null }}>{respuesta}</ReactMarkdown>
```

## 9. Redirecciones, subidas y headers (X3, 13, 17)

```ts
// Redirección: solo rutas internas
const destino = req.nextUrl.searchParams.get("next") ?? "/";
const seguro = destino.startsWith("/") && !destino.startsWith("//") && !destino.startsWith("/\\") ? destino : "/";
return NextResponse.redirect(new URL(seguro, req.url));

// Subidas: nombre del servidor, tipo real, tamaño, bucket privado con URL firmada
import { fileTypeFromBuffer } from "file-type";
const buf = Buffer.from(await archivo.arrayBuffer());
if (buf.length > 2_000_000) return NextResponse.json({ error: "Máximo 2 MB" }, { status: 413 });
const tipo = await fileTypeFromBuffer(buf);
if (!tipo || !["image/png", "image/jpeg", "image/webp"].includes(tipo.mime)) return NextResponse.json({ error: "Solo PNG, JPG o WebP" }, { status: 415 });
await supabase.storage.from("avatares").upload(`${user.id}/${crypto.randomUUID()}.${tipo.ext}`, buf, { contentType: tipo.mime, upsert: false });
```
```js
// next.config.js — headers y sin source maps en producción
const headers = [
  { key: "Content-Security-Policy", value: "default-src 'self'; img-src 'self' data: https:; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self' https://*.supabase.co; frame-ancestors 'none'" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=()" },
];
module.exports = { productionBrowserSourceMaps: false, poweredByHeader: false, async headers() { return [{ source: "/(.*)", headers }]; } };
```
La CSP de arriba es un punto de partida: con scripts en línea de Next hace falta nonce (ver la guía de CSP de Next.js
para tu versión) o `'unsafe-inline'` en `script-src` mientras tanto.
