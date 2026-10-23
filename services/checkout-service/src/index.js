const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const jwt = require('jsonwebtoken');
const db = require('./db');
const mq = require('./mq');
const { getProduct } = require('./catalogue');
const { validateItems } = require('./validate');

if (!process.env.JWT_SECRET) { console.error('JWT_SECRET is required'); process.exit(1); }
const SECRET = process.env.JWT_SECRET;

const app = express();
app.set('trust proxy', 2);
app.use(helmet());
app.use(express.json({ limit: '10kb' }));

const limiter = rateLimit({ windowMs: 60 * 1000, limit: 60, standardHeaders: true, legacyHeaders: false });

function auth(req, res, next) {
  const h = req.headers.authorization || '';
  const token = h.startsWith('Bearer ') ? h.slice(7) : '';

  try {
    const p = jwt.verify(token, SECRET, { algorithms: ['HS256'] });
    req.user = { id: Number(p.sub), email: p.email };
    next();
  } catch {
    res.status(401).json({ error: 'Please log in.' });
  }
}

app.get('/api/checkout/health', (_req, res) => res.json({ status: 'ok' }));

app.post('/api/checkout/orders', limiter, auth, async (req, res, next) => {
  try {
    const v = validateItems(req.body);
    if (v.error) return res.status(400).json({ error: v.error });

    const lines = [];
    let totalCents = 0;
    for (const item of v.value) {
      const p = await getProduct(item.productId);
      if (!p) return res.status(400).json({ error: `Product ${item.productId} does not exist.` });
      lines.push({ productId: p.id, name: p.name, priceCents: p.priceCents, quantity: item.quantity });
      totalCents += p.priceCents * item.quantity;
    }

    const order = await db.createOrder(req.user, lines, totalCents);
    // Hand the payment to the Erlang worker through RabbitMQ.
    mq.publish('order.created', { orderId: order.id, userId: req.user.id, email: req.user.email, totalCents, status: 'PENDING' });
    res.status(201).json(order);
  } catch (e) {
    if (e.code === 'CATALOGUE_DOWN') return res.status(503).json({ error: 'The catalogue is unavailable. Try again shortly.' });
    next(e);

  }
});

app.get('/api/checkout/orders', limiter, auth, async (req, res, next) => {
  try { res.json(await db.listOrders(req.user.id)); } catch (e) { next(e); }
});

app.get('/api/checkout/orders/:id', limiter, auth, async (req, res, next) => {
  try {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id < 1) return res.status(400).json({ error: 'Invalid order id.' });
    const order = await db.getOrder(req.user.id, id);
    if (!order) return res.status(404).json({ error: 'Order not found.' });
    res.json(order);
  } catch (e) { next(e); }
});

app.use((err, _req, res, _next) => {
  if (err.status && err.status < 500) return res.status(err.status).json({ error: 'Bad request.' });
  console.error(err.message);
  res.status(500).json({ error: 'Something went wrong.' });
});

async function main() {
  await db.init();
  await mq.start(async (msg) => {
    if (!Number.isInteger(msg.orderId) || !['PAID', 'FAILED'].includes(msg.status)) throw new Error('unexpected message');
    const changed = await db.applyResult(msg.orderId, msg.status, msg.reason);
    console.log(`Order ${msg.orderId} -> ${msg.status}${changed ? '' : ' (already final)'}`);
  });
  const server = app.listen(process.env.PORT || 8080, () => console.log('checkout-service listening'));
  const stop = () => server.close(() => db.close().then(() => process.exit(0)));

  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
main().catch((e) => { console.error(e); process.exit(1); });
