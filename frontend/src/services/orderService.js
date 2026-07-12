import { supabase } from '@/lib/supabaseClient';
import { cartService } from '@/services/cartService';
import { canCustomerCancel } from '@/utils/orderStatus';

const ORDER_SELECT = `
  *,
  order_items (*),
  profiles (full_name, email, phone),
  pickup_locations (id, name, building, description, operating_hours)
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

  const deliveryFee = Number(row.delivery_fee ?? 0);
  const totalAmount = Number(row.total ?? row.total_amount ?? row.total_price ?? 0);
  const subtotal = Math.max(0, totalAmount - deliveryFee);

  const pickup = row.pickup_locations || null;

  return {
    id: row.id,
    _id: row.id,
    orderNumber: `#${String(row.id).slice(0, 8).toUpperCase()}`,
    orderStatus: row.status,
    status: row.status,
    paymentStatus: row.payment_status,
    totalAmount,
    total_amount: totalAmount,
    subtotal,
    deliveryFee,
    deliveryType: row.delivery_type || null,
    pickupLocationId: row.pickup_location_id || null,
    pickupLocation: pickup
      ? {
          id: pickup.id,
          name: pickup.name,
          building: pickup.building,
          description: pickup.description,
          operatingHours: pickup.operating_hours,
        }
      : null,
    deliveryAddress: row.delivery_address || null,
    customerNote: row.customer_note || null,
    customerPhone: row.profiles?.phone || row.delivery_address?.phone || null,
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

export const validateBeforeCheckout = async (userId) => {
  return cartService.validateCartStock(userId);
};

export const placeOrder = async (userId, fulfillment = {}) => {
  const validation = await validateBeforeCheckout(userId);
  if (validation.error) throw validation.error;
  if (!validation.valid) {
    const message = validation.issues?.[0]?.error || 'Cart validation failed';
    throw new Error(message);
  }

  const { data, error } = await supabase.rpc('place_order', {
    p_user_id: userId,
    p_delivery_type: fulfillment.deliveryType || null,
    p_pickup_location_id: fulfillment.pickupLocationId || null,
    p_delivery_address: fulfillment.deliveryAddress || null,
    p_customer_note: fulfillment.customerNote || null,
  });
  if (error) throw error;
  return { order: { id: data } };
};

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

export const getActivePickupLocations = async () => {
  const { data, error } = await supabase
    .from('pickup_locations')
    .select('id, name, building, description, operating_hours')
    .eq('is_active', true)
    .order('name', { ascending: true });

  if (error) throw error;
  return {
    data: (data || []).map((loc) => ({
      id: loc.id,
      name: loc.name,
      building: loc.building,
      description: loc.description,
      operatingHours: loc.operating_hours,
    })),
  };
};

export const getOrderEvents = async (orderId) => {
  const { data, error } = await supabase
    .from('order_events')
    .select('id, event_type, payload, created_at')
    .eq('order_id', orderId)
    .order('created_at', { ascending: true });

  if (error) throw error;
  return { data: data || [] };
};

export const canCancelOrder = (status, isAdmin = false) => {
  if (isAdmin) return status && status !== 'delivered' && status !== 'cancelled';
  return canCustomerCancel(status);
};

export const orderService = {
  placeOrder,
  validateBeforeCheckout,
  cancelOrder,
  getOrder,
  getMyOrders,
  getActivePickupLocations,
  getOrderEvents,
  canCancelOrder,
  mapOrder,
};
