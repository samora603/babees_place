/** Order status transitions and cancellation rules (mirrors 013 RPCs). */

export const ORDER_STATUS_FLOW = {
  pending: { label: 'Pending', next: ['confirmed'] },
  confirmed: { label: 'Confirmed', next: ['processing', 'ready_for_pickup'] },
  processing: { label: 'Processing', next: ['shipped'] },
  ready_for_pickup: { label: 'Ready for Pickup', next: ['delivered'] },
  shipped: { label: 'Shipped', next: ['delivered'] },
  delivered: { label: 'Delivered', next: [] },
  cancelled: { label: 'Cancelled', next: [] },
};

/** Timeline steps shown to customers (subset varies by delivery type). */
export const PICKUP_TIMELINE = ['pending', 'confirmed', 'ready_for_pickup', 'delivered'];
export const DELIVERY_TIMELINE = ['pending', 'confirmed', 'processing', 'shipped', 'delivered'];

export const CUSTOMER_CANCELLABLE = ['pending', 'confirmed'];

export const TERMINAL_STATUSES = ['delivered', 'cancelled'];

/** Flat delivery fee (KES) — must match place_order() in 013. */
export const DELIVERY_FEE = 200;

/**
 * Allowed admin transitions for a given order status and delivery type.
 */
export function getAllowedNextStatuses(currentStatus, deliveryType) {
  if (TERMINAL_STATUSES.includes(currentStatus)) return [];

  if (currentStatus === 'pending') return ['confirmed'];

  if (currentStatus === 'confirmed') {
    if (deliveryType === 'pickup') return ['ready_for_pickup'];
    if (deliveryType === 'delivery') return ['processing'];
    return ['processing', 'ready_for_pickup'];
  }

  if (currentStatus === 'processing') return ['shipped'];
  if (currentStatus === 'ready_for_pickup') return ['delivered'];
  if (currentStatus === 'shipped') return ['delivered'];

  return [];
}

export function canCustomerCancel(status) {
  return CUSTOMER_CANCELLABLE.includes(status);
}

export function canAdminCancel(status) {
  return status && !TERMINAL_STATUSES.includes(status);
}

export function getTimelineSteps(deliveryType) {
  return deliveryType === 'pickup' ? PICKUP_TIMELINE : DELIVERY_TIMELINE;
}

export function isTransitionAllowed(from, to, deliveryType) {
  return getAllowedNextStatuses(from, deliveryType).includes(to);
}
