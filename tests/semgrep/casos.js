app.post('/webhook/mercadopago', async (req, res) => { await marcarPagado(req.body.data.id); res.sendStatus(200); });
app.post('/webhook/stripe', express.raw({type: 'application/json'}), (req, res) => {
  const ev = stripe.webhooks.constructEvent(req.body, req.headers['stripe-signature'], secreto);
  res.sendStatus(200);
});
app.post('/api/login', (req, res) => res.send('x'));
function pintar(caja, respuesta) { caja.innerHTML = respuesta.choices[0].message.content; }
function pintar2(caja, texto) { caja.innerHTML = texto; }
const codigo = Math.floor(Math.random() * 1e6);
const offset = Math.random();
