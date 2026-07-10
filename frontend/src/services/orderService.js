import { supabase } from '@/lib/supabaseClient';

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

  const totalAmount = Number(row.total_amount ?? row.total_price ?? 0);

  return {
    id: row.id,
    _id: row.id,
    orderNumber: `#${String(row.id).slice(0, 8).toUpperCase()}`,
    orderStatus: row.status ?? row.order_status,
    status: row.status ?? row.order_status,
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
 * Place order via atomic RPC (validates stock, creates order/items, decrements stock, clears cart).
 */
export const placeOrder = async (userId) => {
  const { data, error } = await supabase.rpc('place_order', { p_user_id: userId });
  if (error) throw error;
  return { order: { id: data } };
};

/**
 * Fallback client-side order creation (used if RPC unavailable).
 */
export const createOrderFromCart = async (userId, cartItems) => {
  if (!userId || !cartItems?.length) {
    throw new Error('Invalid order request');
  }

  const totalAmount = cartItems.reduce((sum, item) => {
    const product = item.product || {};
    const price = Number(product.discountPrice ?? product.price ?? 0);
    return sum + price * Number(item.quantity || 1);
  }, 0);

  const { data: order, error: orderError } = await supabase
    .from('orders')
    .insert({
      user_id: userId,
      total_amount: totalAmount,
      status: 'pending',
      payment_status: 'pending',
    })
    .select()
    .single();

  if (orderError) throw orderError;

  const orderItems = cartItems.map((item) => {
    const product = item.product || {};
    const price = Number(product.discountPrice ?? product.price ?? 0);
    const image = product.image_url
      || (Array.isArray(product.images) && product.images[0]?.url)
      || null;

    return {
      order_id: order.id,
      product_id: item.product_id,
      name: product.name || 'Unknown',
      price,
      quantity: Number(item.quantity || 1),
      image_url: image,
    };
  });

  const { error: itemsError } = await supabase
    .from('order_items')
    .insert(orderItems);

  if (itemsError) {
    await supabase.from('orders').delete().eq('id', order.id);
    throw itemsError;
  }

  for (const item of cartItems) {
    const product = item.product;
    if (!product?.id) continue;
    const newStock = Number(product.stock ?? 0) - Number(item.quantity || 1);
    if (newStock < 0) {
      await supabase.from('orders').delete().eq('id', order.id);
      throw new Error(`Insufficient stock for ${product.name}`);
    }
    await supabase.from('products').update({ stock: newStock }).eq('id', product.id);
  }

  return { order };
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
  createOrderFromCart,
  getOrder,
  getMyOrders,
  mapOrder,
};
