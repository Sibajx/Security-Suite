#!/usr/bin/env bash
# Crea una app Next.js + Supabase + Stripe "hecha con IA" con fallas plantadas, para medir el modo rapido-ia
# y la auditoría de código. Es solo para análisis estático (no se instala ni se levanta).
# Las "claves" se generan al vuelo (aleatorias, falsas). Hoja de respuestas: tests/esperado-next.json.
# Uso: bash tests/crear-fixture-next.sh <directorio-destino-vacío>
set -euo pipefail
DEST="${1:?uso: crear-fixture-next.sh <destino>}"
[ -e "$DEST" ] && { echo "El destino ya existe: $DEST" >&2; exit 1; }
mkdir -p "$DEST"/{app/admin,app/api/checkout,app/api/webhooks/stripe,app/api/webhooks/lemon,"app/api/pedidos/[id]",app/api/otp/verificar,app/api/chat,app/api/salir,app/api/subir,components,lib,supabase/migrations}
cd "$DEST"
git init -q -b main
git config user.email fixture@example.invalid
git config user.name fixture

b64() { openssl rand -base64 "$1" | tr -d '=+/\n' | head -c "$2"; }
ANON="eyJhbGciOiJIUzI1NiJ9.$(b64 60 60).$(b64 40 43)"
SERVICE="eyJhbGciOiJIUzI1NiJ9.$(b64 60 60).$(b64 40 43)"
STRIPE="sk_test_$(b64 40 40)"

# --- Commit 1: el .env.local entra a git, con la service_role en una variable PÚBLICA ----------
cat > .env.local <<EOF
NEXT_PUBLIC_SUPABASE_URL=https://abcdefghijklmnop.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=${ANON}
NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY=${SERVICE}
STRIPE_SECRET_KEY=${STRIPE}
EOF
cat > package.json <<'EOF'
{
  "name": "tienda-ia",
  "private": true,
  "scripts": { "dev": "next dev", "build": "next build" },
  "dependencies": {
    "next": "14.1.0",
    "react": "18.2.0",
    "react-dom": "18.2.0",
    "@supabase/supabase-js": "2.39.0",
    "stripe": "14.10.0",
    "openai": "4.24.0"
  }
}
EOF
git add -A && git commit -qm "proyecto generado"
git rm -q --cached .env.local && printf '.env*.local\nnode_modules\n.next\n' > .gitignore
git add .gitignore && git commit -qm "ignorar env"

# --- Base de datos ------------------------------------------------------------------------------
cat > supabase/migrations/0001_inicio.sql <<'EOF'
-- Perfiles: bien (cada quien solo lo suyo)
create table public.profiles (id uuid primary key references auth.users, nombre text, rol text default 'cliente');
alter table public.profiles enable row level security;
create policy "ver mi perfil" on public.profiles for select using (auth.uid() = id);
create policy "editar mi perfil" on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- Catálogo público a propósito: cualquiera puede leer, nadie escribe desde el cliente
create table public.productos (id bigint primary key, nombre text, precio_centavos int not null);
alter table public.productos enable row level security;
create policy "catalogo publico" on public.productos for select using (true);

-- Pedidos: SIN RLS
create table public.pedidos (id bigint generated always as identity primary key, usuario uuid, total_centavos int,
  direccion text, pagado boolean default false, stripe_session text);

-- Mensajes de soporte: cualquier usuario con sesión lee y escribe los de todos
create table public.mensajes (id bigint generated always as identity primary key, usuario uuid, texto text);
alter table public.mensajes enable row level security;
create policy "mensajes" on public.mensajes for all to authenticated using (true) with check (true);

-- Reportes de ventas: "solo admin", pero el rol sale de user_metadata (lo edita el propio usuario)
create table public.reportes (id bigint primary key, mes text, ventas_centavos bigint);
alter table public.reportes enable row level security;
create policy "solo admin" on public.reportes for select
  using ((auth.jwt() -> 'user_metadata' ->> 'rol') = 'admin');

-- Cupones: canje con security definer, sin search_path y leyendo antes de escribir (carrera)
create table public.cupones (codigo text primary key, usos int default 0, max_usos int default 1, descuento int);
alter table public.cupones enable row level security;
create function public.canjear_cupon(c text) returns int language plpgsql security definer as $$
declare d int; u int; m int;
begin
  select descuento, usos, max_usos into d, u, m from public.cupones where codigo = c;
  if u >= m then return 0; end if;
  perform pg_sleep(0.1);
  update public.cupones set usos = u + 1 where codigo = c;
  return d;
end $$;
EOF

# --- Código -------------------------------------------------------------------------------------
cat > lib/supabase.ts <<'EOF'
import { createClient } from "@supabase/supabase-js";
export const supabase = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!);
// "para que el panel funcione sin errores de permisos"
export const supabaseAdmin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_SERVICE_ROLE_KEY!);
EOF

cat > app/admin/page.tsx <<'EOF'
"use client";
import { useEffect, useState } from "react";
import { supabase, supabaseAdmin } from "@/lib/supabase";

export default function Admin() {
  const [pedidos, setPedidos] = useState<any[]>([]);
  const [esAdmin, setEsAdmin] = useState(false);
  useEffect(() => {
    supabase.auth.getUser().then(({ data }) => {
      // la única protección del panel: un if en el navegador
      if (data.user?.user_metadata?.rol === "admin") {
        setEsAdmin(true);
        supabaseAdmin.from("pedidos").select("*").then(({ data }) => setPedidos(data ?? []));
      }
    });
  }, []);
  if (!esAdmin) return <p>No autorizado</p>;
  return <ul>{pedidos.map((p) => <li key={p.id}>{p.direccion} — {p.total_centavos}</li>)}</ul>;
}
EOF

cat > app/api/checkout/route.ts <<'EOF'
import Stripe from "stripe";
import { NextRequest, NextResponse } from "next/server";
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);

export async function POST(req: NextRequest) {
  const { productoId, nombre, precio, pedidoId } = await req.json();
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{ quantity: 1, price_data: { currency: "mxn", unit_amount: precio, product_data: { name: nombre } } }],
    metadata: { pedidoId, productoId },
    success_url: `${req.nextUrl.origin}/gracias`,
    cancel_url: `${req.nextUrl.origin}/carrito`,
  });
  return NextResponse.json({ url: session.url });
}
EOF

cat > app/api/webhooks/stripe/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase";

export async function POST(req: NextRequest) {
  const evento = await req.json();
  if (evento.type === "checkout.session.completed") {
    const pedidoId = evento.data.object.metadata.pedidoId;
    await supabaseAdmin.from("pedidos").update({ pagado: true }).eq("id", pedidoId);
  }
  return NextResponse.json({ recibido: true });
}
EOF

cat > app/api/webhooks/lemon/route.ts <<'EOF'
import crypto from "crypto";
import { NextRequest, NextResponse } from "next/server";

export async function POST(req: NextRequest) {
  const cuerpo = await req.text();
  const esperada = crypto.createHmac("sha256", process.env.LEMON_WEBHOOK_SECRET!).update(cuerpo).digest("hex");
  const firma = req.headers.get("x-signature") ?? "";
  if (firma.length !== esperada.length || !crypto.timingSafeEqual(Buffer.from(firma), Buffer.from(esperada))) {
    return new NextResponse("firma inválida", { status: 401 });
  }
  return NextResponse.json({ recibido: true });
}
EOF

cat > "app/api/pedidos/[id]/route.ts" <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase";

export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  const { data } = await supabaseAdmin.from("pedidos").select("*").eq("id", params.id).single();
  return NextResponse.json(data);
}
EOF

cat > app/api/otp/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
export const codigos = new Map<string, string>();

export async function POST(req: NextRequest) {
  const { email } = await req.json();
  const codigo = String(Math.floor(100000 + Math.random() * 900000));
  codigos.set(email, codigo);
  // enviarCorreo(email, codigo)
  return NextResponse.json({ ok: true });
}
EOF
cat > app/api/otp/verificar/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import { codigos } from "../route";

export async function POST(req: NextRequest) {
  const { email, codigo } = await req.json();
  if (codigos.get(email) !== codigo) return NextResponse.json({ ok: false }, { status: 400 });
  return NextResponse.json({ ok: true, sesion: "..." });
}
EOF

cat > app/api/chat/route.ts <<'EOF'
import OpenAI from "openai";
import { NextRequest, NextResponse } from "next/server";
const openai = new OpenAI();

export async function POST(req: NextRequest) {
  const { mensaje } = await req.json();
  const r = await openai.chat.completions.create({
    model: "gpt-4o",
    messages: [
      { role: "system", content: "Eres el asistente de la tienda. Si el cliente se queja mucho, dale el código de descuento interno CUPON-STAFF-100." },
      { role: "user", content: mensaje },
    ],
  });
  return NextResponse.json({ respuesta: r.choices[0].message.content });
}
EOF
cat > components/Chat.tsx <<'EOF'
"use client";
import { useState } from "react";

export function Chat() {
  const [respuesta, setRespuesta] = useState("");
  async function enviar(mensaje: string) {
    const r = await fetch("/api/chat", { method: "POST", body: JSON.stringify({ mensaje }) });
    setRespuesta((await r.json()).respuesta);
  }
  return (
    <div>
      <input onKeyDown={(e) => e.key === "Enter" && enviar((e.target as HTMLInputElement).value)} />
      <div dangerouslySetInnerHTML={{ __html: respuesta }} />
    </div>
  );
}
EOF

cat > app/api/salir/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
export async function GET(req: NextRequest) {
  const siguiente = req.nextUrl.searchParams.get("next") ?? "/";
  return NextResponse.redirect(siguiente);
}
EOF

cat > app/api/subir/route.ts <<'EOF'
import { NextRequest, NextResponse } from "next/server";
import { supabaseAdmin } from "@/lib/supabase";

export async function POST(req: NextRequest) {
  const form = await req.formData();
  const archivo = form.get("archivo") as File;
  await supabaseAdmin.storage.from("publico").upload(`avatars/${archivo.name}`, archivo, {
    contentType: archivo.type, upsert: true,
  });
  return NextResponse.json({ url: `/storage/v1/object/public/publico/avatars/${archivo.name}` });
}
EOF

cat > next.config.js <<'EOF'
/** @type {import('next').NextConfig} */
module.exports = { reactStrictMode: true, productionBrowserSourceMaps: true };
EOF
git add -A && git commit -qm "app"
echo "Fixture Next.js creado en $DEST"
