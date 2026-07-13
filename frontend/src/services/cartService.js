import { supabase } from '@/lib/supabaseClient';
import { validateProductForCart, validateCartForCheckout } from '@/services/inventoryValidation';

const normalizeRows = (rows = []) => rows.map((row) => ({
  id: row.id,
  product_id: row.product_id,
  quantity: Number(row.quantity || 1),
  created_at: row.created_at,
  product: row.products ?? null,
}));

const fetchProductForCart = async (productId) => {
  const { data, error } = await supabase
    .from('products')
    .select('id, name, stock, is_active')
    .eq('id', productId)
    .maybeSingle();
  if (error) return { product: null, error };
  return { product: data, error: null };
};

export const cartService = {
  getCart: async (userId) => {
    try {
      if (!userId) return { data: { items: [] }, error: null };
      const { data, error } = await supabase.from('cart_items').select('*, products(*)').eq('user_id', userId).order('created_at', { ascending: false });
      if (error) {
        console.error('cartService.getCart error:', error);
        return { data: { items: [] }, error };
      }
      return { data: { items: normalizeRows(data || []) }, error: null };
    } catch (err) {
      console.error('cartService.getCart exception:', err);
      return { data: { items: [] }, error: err };
    }
  },

  addToCart: async (userId, productId, quantity = 1) => {
    try {
      if (!userId || !productId) {
        return { data: { items: [] }, error: { message: 'Missing user or product' } };
      }

      const { product, error: productError } = await fetchProductForCart(productId);
      if (productError) return { data: { items: [] }, error: productError };
      if (!product) return { data: { items: [] }, error: { message: 'Product not found' } };

      const { data: existing } = await supabase.from('cart_items').select('*').eq('user_id', userId).eq('product_id', productId).maybeSingle();
      const existingQty = Number(existing?.quantity || 0);
      const validation = validateProductForCart(product, quantity, existingQty);
      if (!validation.valid) {
        return { data: { items: [] }, error: { message: validation.error } };
      }

      const nextQty = existingQty + Number(quantity);
      if (existing) {
        const { data, error } = await supabase.from('cart_items').update({ quantity: nextQty }).eq('id', existing.id).select('*, products(*)').single();
        if (error) return { data: { items: [] }, error };
        return { data: { items: normalizeRows([data]) }, error: null };
      }
      const { data, error } = await supabase.from('cart_items').insert({ user_id: userId, product_id: productId, quantity: Number(quantity) }).select('*, products(*)').single();
      if (error) return { data: { items: [] }, error };
      return { data: { items: normalizeRows([data]) }, error: null };
    } catch (err) {
      console.error('cartService.addToCart exception:', err);
      return { data: { items: [] }, error: err };
    }
  },

  updateQuantity: async (cartId, quantity) => {
    try {
      if (Number(quantity) <= 0) {
        return cartService.removeFromCart(cartId);
      }

      const { data: line, error: lineError } = await supabase
        .from('cart_items')
        .select('*, products(id, name, stock, is_active)')
        .eq('id', cartId)
        .maybeSingle();

      if (lineError) return { data: { items: [] }, error: lineError };
      if (!line) return { data: { items: [] }, error: { message: 'Cart item not found' } };

      const validation = validateProductForCart(line.products, quantity, 0);
      if (!validation.valid) {
        return { data: { items: [] }, error: { message: validation.error } };
      }

      const { data, error } = await supabase.from('cart_items').update({ quantity: Number(quantity) }).eq('id', cartId).select('*, products(*)').single();
      if (error) return { data: { items: [] }, error };
      return { data: { items: normalizeRows([data]) }, error: null };
    } catch (err) {
      console.error('cartService.updateQuantity exception:', err);
      return { data: { items: [] }, error: err };
    }
  },

  removeFromCart: async (cartId) => {
    try {
      const { error } = await supabase.from('cart_items').delete().eq('id', cartId);
      return { data: { items: [] }, error };
    } catch (err) {
      console.error('cartService.removeFromCart exception:', err);
      return { data: { items: [] }, error: err };
    }
  },

  clearCart: async (userId) => {
    try {
      if (!userId) return { data: { items: [] }, error: null };
      const { error } = await supabase.from('cart_items').delete().eq('user_id', userId);
      return { data: { items: [] }, error };
    } catch (err) {
      console.error('cartService.clearCart exception:', err);
      return { data: { items: [] }, error: err };
    }
  },

  /** Re-fetch cart with fresh product stock for checkout validation. */
  validateCartStock: async (userId) => {
    const { data, error } = await cartService.getCart(userId);
    if (error) return { valid: false, issues: [], error };
    const result = validateCartForCheckout(data.items || []);
    return { ...result, error: null };
  },

  // Compatibility helpers for existing UI/pages.
  getCartLegacy: async () => {
    const { data: { user } } = await supabase.auth.getUser();
    return cartService.getCart(user?.id);
  },

  addToCartLegacy: async (body) => {
    const { data: { user } } = await supabase.auth.getUser();
    return cartService.addToCart(user?.id, body.productId, body.quantity || 1);
  },

  updateCartItem: async (cartId, quantity) => cartService.updateQuantity(cartId, quantity),
  removeFromCartLegacy: async (cartId) => cartService.removeFromCart(cartId),
};

export const getCart = (userId) => cartService.getCart(userId);
export const addToCart = (userId, productId) => cartService.addToCart(userId, productId);
export const updateQuantity = (cartId, quantity) => cartService.updateQuantity(cartId, quantity);
export const removeFromCart = (cartId) => cartService.removeFromCart(cartId);
export const clearCart = (userId) => cartService.clearCart(userId);
