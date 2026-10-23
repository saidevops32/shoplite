const { Pool } = require('pg');

// PGHOST, PGUSER, PGPASSWORD, PGDATABASE are read by pg itself. Azure needs TLS (PGSSL=true).
const pool = new Pool({
  max: 5,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});
pool.on('error', (e) => console.error('Idle database client error:', e.message));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function init() {
  for (let i = 0; i < 40; i++) {
    try {
      await pool.query(`CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        email TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT now())`);
      console.log('Database ready');
      return;
    } catch (err) {
      console.log('Database not ready, retrying in 3s...');
      await sleep(3000);
    }
  }
  throw new Error('Database unreachable');
}

// Parameterised queries only ($1, $2) to prevent SQL injection.
const createUser = async (email, name, hash) =>
  (await pool.query('INSERT INTO users (email, name, password_hash) VALUES ($1, $2, $3) RETURNING id, email, name', [email, name, hash])).rows[0];

const findByEmail = async (email) =>
  (await pool.query('SELECT id, email, name, password_hash FROM users WHERE email = $1', [email])).rows[0];

const close = () => pool.end();

module.exports = { init, createUser, findByEmail, close };
