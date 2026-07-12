import { hasAvailableStock } from '@/constants/inventory';

/**
 * Validate a single cart line before checkout (UX layer; place_order is authoritative).
 */
export function validateLineForCheckout(product, quantity) {
  if (!product) {
    return { valid: false, error: 'Product not found' };
  }
  if (product.is_active === false) {
    return { valid: false, error: `${product.name} is no longer available` };
  }
  const qty = Number(quantity) || 0;
  if (qty <= 0) {
    return { valid: false, error: `Invalid quantity for ${product.name}` };
  }
  if ((product.stock ?? 0) < qty) {
    return {
      valid: false,
      error: `Insufficient stock for ${product.name} (only ${product.stock ?? 0} available)`,
    };
  }
  return { valid: true };
}

/**
 * Validate all cart lines before calling place_order RPC.
 */
export function validateCartForCheckout(items = []) {
  const issues = [];
  for (const item of items) {
    const result = validateLineForCheckout(item.product, item.quantity);
    if (!result.valid) {
      issues.push({
        cartId: item.id,
        productId: item.product_id,
        productName: item.product?.name,
        error: result.error,
      });
    }
  }
  return { valid: issues.length === 0, issues };
}

/**
 * Validate product can be added to cart (active + stock).
 */
export function validateProductForCart(product, requestedQty, existingQty = 0) {
  if (!product) {
    return { valid: false, error: 'Product not found' };
  }
  if (product.is_active === false) {
    return { valid: false, error: `${product.name} is no longer available` };
  }
  if (!hasAvailableStock(product.stock)) {
    return { valid: false, error: `${product.name} is out of stock` };
  }
  const total = existingQty + (Number(requestedQty) || 0);
  if (total > (product.stock ?? 0)) {
    return {
      valid: false,
      error: `Only ${product.stock} available for ${product.name}`,
    };
  }
  return { valid: true };
}
