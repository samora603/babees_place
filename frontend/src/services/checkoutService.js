import { customerProfileService } from '@/services/customerProfileService';
import { orderService } from '@/services/orderService';
import { evaluateExpressCheckout, buildExpressFulfillment } from '@/models/fasterCheckout';
import { validateCheckoutForm } from '@/utils/orderValidation';

/**
 * Load checkout bootstrap data (locations + profile bundle).
 */
export async function getCheckoutBootstrap() {
  const [locationsResult, bundleResult] = await Promise.all([
    orderService.getActivePickupLocations(),
    customerProfileService.getProfileBundle(),
  ]);

  const error = bundleResult.error;
  if (error) throw error;

  return {
    pickupLocations: locationsResult.data || [],
    addresses: bundleResult.data?.addresses || [],
    preferences: bundleResult.data?.preferences || null,
  };
}

/**
 * Evaluate express checkout eligibility for the current cart state.
 * @param {object} params
 * @param {import('@/models/preferences').CustomerPreferences | null} params.preferences
 * @param {import('@/models/address').CustomerAddress[]} params.addresses
 * @param {Array<{ id: string, name?: string }>} params.pickupLocations
 * @param {boolean} params.cartValid
 */
export function getExpressCheckoutStatus(params) {
  return evaluateExpressCheckout(params);
}

/**
 * Validate and build fulfillment for express checkout.
 * @param {ReturnType<typeof evaluateExpressCheckout>} evaluation
 * @param {string | null} [customerNote]
 */
export function resolveExpressFulfillment(evaluation, customerNote = null) {
  const fulfillment = buildExpressFulfillment(evaluation, customerNote);
  const validation = validateCheckoutForm({
    deliveryType: fulfillment.deliveryType,
    pickupLocationId: fulfillment.pickupLocationId || '',
    deliveryAddress: fulfillment.deliveryAddress || {},
  });
  if (!validation.valid) {
    throw new Error('Saved checkout details are incomplete. Use standard checkout.');
  }
  return fulfillment;
}

/**
 * Place an express order using saved preferences and default address.
 * @param {string} userId
 * @param {ReturnType<typeof evaluateExpressCheckout>} evaluation
 * @param {string | null} [customerNote]
 */
export async function placeExpressOrder(userId, evaluation, customerNote = null, paymentMethod = 'cod') {
  const fulfillment = resolveExpressFulfillment(evaluation, customerNote);
  return orderService.placeOrder(userId, {
    ...fulfillment,
    paymentMethod: paymentMethod || 'cod',
  });
}

export const checkoutService = {
  getCheckoutBootstrap,
  getExpressCheckoutStatus,
  resolveExpressFulfillment,
  placeExpressOrder,
};
