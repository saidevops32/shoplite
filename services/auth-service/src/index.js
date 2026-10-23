const express = require('express');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const db = require('./db');
const { validateRegister, validateLogin } = require('./validate');

if (!process.env.JWT_SECRET) { console.error('JWT_SECRET is required'); process.exit(1); }
const SECRET = process.env.JWT_SECRET;
// Compared against when the email is unknown, so login takes the same time either way.
const DUMMY_HASH = bcrypt.hashSync('not-a-real-password', 10);

const app = express();
app.set('trust proxy', 2); // Application Gateway + Container Apps ingress in front
app.use(helmet());
app.use(express.json({ limit: '10kb' }));

const limiter = rateLimit({ windowMs: 15 * 60 * 1000, limit: 30, standardHeaders: true, legacyHeaders: false });

const sign = (u) => jwt.sign({ email: u.email, name: u.name }, SECRET, { subject: String(u.id), expiresIn: '12h', algorithm: 'HS256' });
const publicUser = (u) => ({ id: u.id, email: u.email, name: u.name });
const bearer = (req) => {
  const h = req.headers.authorization || '';
  return h.startsWith('Bearer ') ? h.slice(7) : '';
};

app.get('/api/auth/health', (_req, res) => res.json({ status: 'ok' }));

app.post('/api/auth/register', limiter, async (req, res, next) => {
  try {
    const v = validateRegister(req.body);
    if (v.error) return res.status(400).json({ error: v.error });
    const hash = await bcrypt.hash(v.value.password, 10);
    const user = await db.createUser(v.value.email, v.value.name, hash);
    res.status(201).json({ token: sign(user), user: publicUser(user) });
  } catch (e) {
    if (e.code === '23505') return res.status(409).json({ error: 'That email is already registered.' });
    next(e);
  }
});

app.post('/api/auth/login', limiter, async (req, res, next) => {
  try {
    const v = validateLogin(req.body);
    if (v.error) return res.status(400).json({ error: v.error });
    const user = await db.findByEmail(v.value.email);
    const ok = await bcrypt.compare(v.value.password, user ? user.password_hash : DUMMY_HASH);
    if (!user || !ok) return res.status(401).json({ error: 'Invalid email or password.' });
    res.json({ token: sign(user), user: publicUser(user) });
  } catch (e) { next(e); }
});

app.get('/api/auth/me', (req, res) => {
  try {
    const p = jwt.verify(bearer(req), SECRET, { algorithms: ['HS256'] });
    res.json({ id: Number(p.sub), email: p.email, name: p.name });
  } catch {
    res.status(401).json({ error: 'Please log in.' });
  }
});

app.use((err, _req, res, _next) => {
  if (err.status && err.status < 500) return res.status(err.status).json({ error: 'Bad request.' });
  console.error(err.message);
  res.status(500).json({ error: 'Something went wrong.' });
});

async function main() {
  await db.init();
  const server = app.listen(process.env.PORT || 8080, () => console.log('auth-service listening'));
  const stop = () => server.close(() => db.close().then(() => process.exit(0)));
  process.on('SIGTERM', stop);
  process.on('SIGINT', stop);
}
main().catch((e) => { console.error(e); process.exit(1); });
