const test = require('node:test');
const assert = require('node:assert');
const { validateRegister, validateLogin } = require('../src/validate');

test('register: normalises email and trims name', () => {
  const r = validateRegister({ email: '  Sai@Example.COM ', name: ' Sai ', password: 'password123' });
  assert.deepStrictEqual(r.value, { email: 'sai@example.com', name: 'Sai', password: 'password123' });
});
test('register: rejects bad email, short password, empty name', () => {
  assert.ok(validateRegister({ email: 'nope', name: 'A', password: 'password123' }).error);
  assert.ok(validateRegister({ email: 'a@b.co', name: 'A', password: 'short' }).error);
  assert.ok(validateRegister({ email: 'a@b.co', name: '  ', password: 'password123' }).error);
  assert.ok(validateRegister(undefined).error);
});
test('login: needs email and password', () => {
  assert.ok(validateLogin({ email: 'a@b.co' }).error);
  assert.deepStrictEqual(validateLogin({ email: 'A@B.co', password: 'x' }).value, { email: 'a@b.co', password: 'x' });
});
