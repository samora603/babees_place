import { supabase } from '@/lib/supabaseClient';
import { cartService } from '@/services/cartService';

const ORDER_SELECT = `
  *,
  order_items (*),
  profiles (full_name, email, phone)
`;

/**
 * Map Supabase order row to UI-friendly shape (receipt + legacy fields).
 */
export const mapOrder = (row) => {
  if (!row) return null;

  const items = (row.order_items || []).map((item) => ({
    _id: item.id,
    id: item.id,
    product_id: item.product_id,
    name: item.name,
    price: Number(item.price || 0),
    quantity: Number(item.quantity || 1),
    image: item.image_url || item.image || '/placeholder.png',
  }));

  // Canonical column is `orders.total`; keep legacy fallbacks for any cached shapes.
  const totalAmount = Number(row.total ?? row.total_amount ?? row.total_price ?? 0);

  return {
    id: row.id,
    _id: row.id,
    orderNumber: `#${String(row.id).slice(0, 8).toUpperCase()}`,
    orderStatus: row.status,
    status: row.status,
    paymentStatus: row.payment_status,
    totalAmount,
    total_amount: totalAmount,
    subtotal: totalAmount,
    deliveryFee: 0,
    deliveryType: row.delivery_type || null,
    pickupLocation: row.pickup_location || null,
    deliveryAddress: row.delivery_address || null,
    customerPhone: row.profiles?.phone || null,
    mpesaReceiptNumber: row.mpesa_receipt_number || null,
    createdAt: row.created_at,
    created_at: row.created_at,
    note: row.note,
    items,
    order_items: row.order_items,
    user: row.profiles
      ? { name: row.profiles.full_name, email: row.profiles.email, phone: row.profiles.phone }
      : null,
    profiles: row.profiles,
  };
};

/**
 * Client-side pre-check before RPC (UX only; place_order remains authoritative).
 */
export const validateBeforeCheckout = async (userId) => {
  return cartService.validateCartStock(userId);
};

/**
 * Place order via atomic RPC (validates stock, creates order/items, decrements stock, clears cart).
 */
export const placeOrder = async (userId) => {
  const validation = await validateBeforeCheckout(userId);
  if (validation.error) throw validation.error;
  if (!validation.valid) {
    const message = validation.issues?.[0]?.error || 'Cart validation failed';
    throw new Error(message);
  }

  const { data, error } = await supabase.rpc('place_order', { p_user_id: userId });
  if (error) throw error;
  return { order: { id: data } };
};

/**
 * Cancel order and restore stock via cancel_order RPC.
 */
export const cancelOrder = async (orderId) => {
  const { error } = await supabase.rpc('cancel_order', { p_order_id: orderId });
  if (error) throw error;
  return { success: true };
};

export const getOrder = async (orderId) => {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('id', orderId)
    .maybeSingle();

  if (error) throw error;
  return { data: { data: mapOrder(data) } };
};

export const getMyOrders = async (userId) => {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('user_id', userId)
    .order('created_at', { ascending: false });

  if (error) throw error;
  return { data: { data: (data || []).map(mapOrder) } };
};

export const orderService = {
  placeOrder,
  validateBeforeCheckout,
  cancelOrder,
  getOrder,
  getMyOrders,
  mapOrder,
};
