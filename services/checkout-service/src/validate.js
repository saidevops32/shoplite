// Checks the cart sent by the app. Prices are never trusted from the client.
function validateItems(body) {
  const items = body && body.items;
  if (!Array.isArray(items) || items.length < 1 || items.length > 20) return { error: 'Add between 1 and 20 items.' };
  const merged = new Map();
  for (const it of items) {
    const productId = it && it.productId;
    const quantity = it && it.quantity;
    if (!Number.isInteger(productId) || productId < 1) return { error: 'Invalid product.' };
    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 20) return { error: 'Quantity must be 1 to 20.' };

    merged.set(productId, (merged.get(productId) || 0) + quantity);
  }
  for (const q of merged.values()) if (q > 20) return { error: 'Maximum 20 of one product.' };
  return { value: [...merged].map(([productId, quantity]) => ({ productId, quantity })) };
}

module.exports = { validateItems };
