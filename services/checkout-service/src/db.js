const { Pool } = require('pg');

const pool = new Pool({
  max: 5,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});
pool.on('error', (e) => console.error('Idle database client error:', e.message));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function init() {
  for (let i = 0; i < 40; i++) {
    try {
      await pool.query(`CREATE TABLE IF NOT EXISTS orders (

        id SERIAL PRIMARY KEY,
        user_id INTEGER NOT NULL,
        user_email TEXT NOT NULL,
        total_cents INTEGER NOT NULL CHECK (total_cents >= 0),
        status TEXT NOT NULL DEFAULT 'PENDING',
        reason TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
      await pool.query(`CREATE TABLE IF NOT EXISTS order_items (
        id SERIAL PRIMARY KEY,
        order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        product_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        price_cents INTEGER NOT NULL CHECK (price_cents >= 0),
        quantity INTEGER NOT NULL CHECK (quantity > 0))`);
      await pool.query('CREATE INDEX IF NOT EXISTS idx_orders_user ON orders(user_id)');
      console.log('Database ready');
      return;
    } catch (err) {
      console.log('Database not ready, retrying in 3s...');
      await sleep(3000);
    }
  }
  throw new Error('Database unreachable');
}

const toOrder = (r, items) => ({
  id: r.id,
  totalCents: r.total_cents,
  status: r.status,
  reason: r.reason || '',
  createdAt: r.created_at,

  items: items || r.items || [],
});

// Order and its lines are saved together or not at all.
async function createOrder(user, lines, totalCents) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const o = (await client.query(
      'INSERT INTO orders (user_id, user_email, total_cents) VALUES ($1, $2, $3) RETURNING *',
      [user.id, user.email, totalCents]
    )).rows[0];
    for (const l of lines) {
      await client.query(
        'INSERT INTO order_items (order_id, product_id, name, price_cents, quantity) VALUES ($1, $2, $3, $4, $5)',
        [o.id, l.productId, l.name, l.priceCents, l.quantity]
      );
    }
    await client.query('COMMIT');
    return toOrder(o, lines);
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

const ORDER_SELECT = `
  SELECT o.*, COALESCE(json_agg(json_build_object(
           'productId', i.product_id, 'name', i.name, 'priceCents', i.price_cents, 'quantity', i.quantity
         ) ORDER BY i.id) FILTER (WHERE i.id IS NOT NULL), '[]') AS items

  FROM orders o LEFT JOIN order_items i ON i.order_id = o.id`;

async function listOrders(userId) {
  const r = await pool.query(`${ORDER_SELECT} WHERE o.user_id = $1 GROUP BY o.id ORDER BY o.id DESC LIMIT 50`, [userId]);
  return r.rows.map((x) => toOrder(x));
}

async function getOrder(userId, id) {
  const r = await pool.query(`${ORDER_SELECT} WHERE o.user_id = $1 AND o.id = $2 GROUP BY o.id`, [userId, id]);
  return r.rows[0] ? toOrder(r.rows[0]) : null;
}

// Only a PENDING order can change, so a repeated message does no harm.
async function applyResult(orderId, status, reason) {
  const r = await pool.query(
    "UPDATE orders SET status = $2, reason = $3, updated_at = now() WHERE id = $1 AND status = 'PENDING' RETURNING id",
    [orderId, status, reason || '']
  );
  return r.rowCount > 0;
}

const close = () => pool.end();

module.exports = { init, createOrder, listOrders, getOrder, applyResult, close };
