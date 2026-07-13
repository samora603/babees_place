import { getDefaultAddress, addressToCheckoutDelivery } from '@/models/address';
import { validateCheckoutForm, buildDeliveryAddressPayload } from '@/utils/orderValidation';

/**
 * Determine whether a returning customer can use express (one-click) checkout.
 * @param {object} params
 * @param {import('@/models/preferences').CustomerPreferences | null} params.preferences
 * @param {import('@/models/address').CustomerAddress[]} params.addresses
 * @param {Array<{ id: string }>} params.pickupLocations
 * @param {boolean} params.cartValid
 */
export function evaluateExpressCheckout({
  preferences,
  addresses = [],
  pickupLocations = [],
  cartValid = false,
}) {
  if (!cartValid) {
    return { eligible: false, reason: 'cart_invalid' };
  }

  const deliveryType = preferences?.preferredFulfillment;
  if (!deliveryType || !['pickup', 'delivery'].includes(deliveryType)) {
    return { eligible: false, reason: 'no_fulfillment_preference' };
  }

  if (deliveryType === 'pickup') {
    const pickupLocationId = preferences?.preferredPickupLocationId;
    if (!pickupLocationId) {
      return { eligible: false, reason: 'no_pickup_location' };
    }
    const location = pickupLocations.find((loc) => loc.id === pickupLocationId);
    if (!location) {
      return { eligible: false, reason: 'pickup_location_unavailable' };
    }
    return {
      eligible: true,
      deliveryType: 'pickup',
      pickupLocationId,
      summary: `Pickup at ${location.name}`,
      location,
    };
  }

  const defaultAddress = getDefaultAddress(addresses);
  if (!defaultAddress) {
    return { eligible: false, reason: 'no_default_address' };
  }

  const deliveryAddress = addressToCheckoutDelivery(defaultAddress);
  const validation = validateCheckoutForm({
    deliveryType: 'delivery',
    pickupLocationId: '',
    deliveryAddress,
  });

  if (!validation.valid) {
    return { eligible: false, reason: 'invalid_default_address' };
  }

  return {
    eligible: true,
    deliveryType: 'delivery',
    defaultAddress,
    deliveryAddress,
    summary: `Delivery to ${defaultAddress.streetAddress}, ${defaultAddress.town}`,
  };
}

/**
 * Build fulfillment payload for express checkout from evaluation result.
 * @param {ReturnType<typeof evaluateExpressCheckout>} evaluation
 * @param {string | null} [customerNote]
 */
export function buildExpressFulfillment(evaluation, customerNote = null) {
  if (!evaluation?.eligible) {
    throw new Error('Express checkout is not available');
  }

  if (evaluation.deliveryType === 'pickup') {
    return {
      deliveryType: 'pickup',
      pickupLocationId: evaluation.pickupLocationId,
      deliveryAddress: null,
      customerNote: customerNote?.trim() || null,
    };
  }

  return {
    deliveryType: 'delivery',
    pickupLocationId: null,
    deliveryAddress: buildDeliveryAddressPayload(evaluation.deliveryAddress),
    customerNote: customerNote?.trim() || null,
  };
}

/**
 * Summarize reorder results for UI messaging.
 * @param {{ added: object[], skipped: Array<{ item: object, reason: string }> }} result
 */
export function summarizeReorderResult(result) {
  const addedCount = result.added?.length || 0;
  const skippedCount = result.skipped?.length || 0;

  if (addedCount === 0 && skippedCount === 0) {
    return { success: false, message: 'This order has no items to reorder.' };
  }
  if (addedCount === 0) {
    return {
      success: false,
      message: 'No items could be added — products may be unavailable or out of stock.',
    };
  }
  if (skippedCount > 0) {
    return {
      success: true,
      partial: true,
      message: `${addedCount} item(s) added to cart. ${skippedCount} could not be added.`,
    };
  }
  return {
    success: true,
    partial: false,
    message: `${addedCount} item(s) added to cart.`,
  };
}
