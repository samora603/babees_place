import { supabase } from '@/lib/supabaseClient';
import { cartService } from '@/services/cartService';
import { canCustomerCancel } from '@/utils/orderStatus';
import { attachProfilesToOrders } from '@/services/profileLookup';
import { notificationService } from '@/services/notificationService';
import { NOTIFICATION_EVENTS } from '@/models/notification';

/**
 * Order select without `profiles` embed.
 * orders.user_id references auth.users, not profiles — embedding profiles
 * causes PostgREST PGRST200 and breaks every order read path.
 */
const ORDER_SELECT = `
  *,
  order_items (*),
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
    paymentMethod: row.payment_method || 'cod',
    discountAmount: Number(row.discount_amount || 0),
    couponCode: row.coupon_code || null,
    loyaltyPointsRedeemed: row.loyalty_points_redeemed || 0,
    giftCardAmount: Number(row.gift_card_amount || 0),
    freeDelivery: Boolean(row.free_delivery),
    promotionsApplied: row.promotions_applied || [],
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
    p_payment_method: fulfillment.paymentMethod || 'cod',
    p_coupon_code: fulfillment.couponCode || null,
    p_loyalty_points: fulfillment.loyaltyPoints || 0,
    p_gift_card_code: fulfillment.giftCardCode || null,
    p_gift_card_amount: fulfillment.giftCardAmount || 0,
    p_discount_amount: fulfillment.discountAmount || 0,
    p_free_delivery: Boolean(fulfillment.freeDelivery),
    p_promotions_applied: fulfillment.promotionsApplied || [],
    p_referral_code: fulfillment.referralCode || null,
  });
  if (error) throw error;

  const orderId = data;
  notificationService.emitSafe(NOTIFICATION_EVENTS.ORDER_CREATED, {
    userId,
    orderId,
    email: fulfillment.email,
    phone: fulfillment.phone,
    name: fulfillment.name,
    amount: fulfillment.amount,
    currency: 'KES',
    paymentMethod: fulfillment.paymentMethod || 'cod',
  });
  notificationService.emitSafe(NOTIFICATION_EVENTS.ADMIN_NEW_ORDER, {
    orderId,
    amount: fulfillment.amount,
    currency: 'KES',
    paymentMethod: fulfillment.paymentMethod || 'cod',
    notifyAdmins: true,
  });

  return { order: { id: orderId } };
};

export const cancelOrder = async (orderId) => {
  const { data: orderRow } = await supabase
    .from('orders')
    .select('id, user_id')
    .eq('id', orderId)
    .maybeSingle();

  const { error } = await supabase.rpc('cancel_order', { p_order_id: orderId });
  if (error) throw error;

  if (orderRow?.user_id) {
    notificationService.emitSafe(NOTIFICATION_EVENTS.ORDER_CANCELLED, {
      userId: orderRow.user_id,
      orderId,
    });
  }

  return { success: true };
};

export const getOrder = async (orderId) => {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('id', orderId)
    .maybeSingle();

  if (error) throw error;
  const enriched = await attachProfilesToOrders(data);
  return { data: { data: mapOrder(enriched) } };
};

export const getMyOrders = async (userId) => {
  const { data, error } = await supabase
    .from('orders')
    .select(ORDER_SELECT)
    .eq('user_id', userId)
    .order('created_at', { ascending: false });

  if (error) throw error;
  const enriched = await attachProfilesToOrders(data || []);
  return { data: { data: enriched.map(mapOrder) } };
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

/**
 * Add all items from a prior order to the customer's cart (merge quantities).
 * @param {string} orderId
 * @param {string} userId
 * @returns {Promise<{ added: object[], skipped: Array<{ item: object, reason: string }> }>}
 */
export const reorder = async (orderId, userId) => {
  const { data } = await getOrder(orderId);

  const order = data?.data;
  if (!order) throw new Error('Order not found');

  const items = order.items || [];
  const added = [];
  const skipped = [];

  for (const item of items) {
    if (!item.product_id) {
      skipped.push({ item, reason: 'Product no longer available' });
      continue;
    }

    const { error: addError } = await cartService.addToCart(
      userId,
      item.product_id,
      Number(item.quantity) || 1,
    );

    if (addError) {
      skipped.push({
        item,
        reason: addError.message || 'Could not add to cart',
      });
    } else {
      added.push(item);
    }
  }

  return { added, skipped };
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
  reorder,
  mapOrder,
};
