const test = require('node:test');
const assert = require('node:assert');
const { validateItems } = require('../src/validate');

test('merges duplicate products', () => {
  const r = validateItems({ items: [{ productId: 1, quantity: 2 }, { productId: 1, quantity: 3 }, { productId: 2, quantity: 1 }] });
  assert.deepStrictEqual(r.value, [{ productId: 1, quantity: 5 }, { productId: 2, quantity: 1 }]);
});
test('rejects empty, malformed and oversized carts', () => {
  assert.ok(validateItems({ items: [] }).error);
  assert.ok(validateItems({}).error);
  assert.ok(validateItems({ items: [{ productId: 'x', quantity: 1 }] }).error);
  assert.ok(validateItems({ items: [{ productId: 1, quantity: 0 }] }).error);
  assert.ok(validateItems({ items: [{ productId: 1, quantity: 15 }, { productId: 1, quantity: 15 }] }).error);
});
