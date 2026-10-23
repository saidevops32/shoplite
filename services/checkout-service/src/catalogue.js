// Asks the catalogue service for the real price. Inside the environment the app name is its address.
const BASE = process.env.CATALOGUE_URL || 'http://catalogue';

function down(message) {
  const e = new Error(message);
  e.code = 'CATALOGUE_DOWN';

  return e;
}

async function getProduct(id) {
  let res;
  try {
    res = await fetch(`${BASE}/api/catalogue/products/${encodeURIComponent(id)}`, { signal: AbortSignal.timeout(5000) });
  } catch {
    throw down('catalogue unreachable');
  }
  if (res.status === 404) return null;
  if (!res.ok) throw down(`catalogue returned ${res.status}`);
  return res.json();
}

module.exports = { getProduct };
