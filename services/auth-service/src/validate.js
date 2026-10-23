const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const str = (v) => (typeof v === 'string' ? v : '');

function validateRegister(body) {
  const b = body || {};
  const email = str(b.email).trim().toLowerCase();
  const name = str(b.name).trim();
  const password = str(b.password);
  if (!EMAIL.test(email) || email.length > 254) return { error: 'Enter a valid email address.' };
  if (name.length < 1 || name.length > 60) return { error: 'Name must be 1 to 60 characters.' };
  if (password.length < 8 || Buffer.byteLength(password) > 72) return { error: 'Password must be 8 to 72 characters.' };
  return { value: { email, name, password } };
}

function validateLogin(body) {
  const b = body || {};
  const email = str(b.email).trim().toLowerCase();
  const password = str(b.password);
  if (!email || !password || password.length > 72) return { error: 'Enter your email and password.' };
  return { value: { email, password } };
}

module.exports = { validateRegister, validateLogin };
