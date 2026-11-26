export async function GET(req, { params }) {
  const { data: { user } } = await supabase.auth.getUser();
  const a = await supabase.from("pedidos").select("*").eq("usuario", user.id).eq("id", params.id).single();
  const b = await supabase.from("pedidos").select("*").eq("id", params.id).eq("usuario", user.id).single();
  const c = await prisma.pedido.findFirst({ where: { id: params.id, userId: user.id } });
  const d = await prisma.pedido.findUnique({ where: { id: params.id } });
  const precio = await db.precio(productoId);
  const s = await stripe.checkout.sessions.create({ line_items: [{ price_data: { unit_amount: precio } }] });
  return NextResponse.redirect(new URL("/gracias", req.url));
}
