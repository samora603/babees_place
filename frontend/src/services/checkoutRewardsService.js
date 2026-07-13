import { DELIVERY_FEE } from '@/utils/orderStatus';
import { promotionService } from '@/services/promotionService';
import { couponService } from '@/services/couponService';
import { loyaltyService } from '@/services/loyaltyService';
import { giftCardService } from '@/services/giftCardService';
import { previewCheckoutRewards } from '@/services/rewardEngine';

/**
 * Build checkout reward preview from live catalog + user inputs.
 */
export async function buildCheckoutRewardPreview({
  cartLines,
  userId,
  deliveryType,
  couponCode,
  loyaltyPointsToRedeem = 0,
  giftCardCode,
  giftCardAmount = null,
}) {
  const [promotions, loyaltyAccount, loyaltyRule] = await Promise.all([
    promotionService.listActivePromotions().catch(() => []),
    userId ? loyaltyService.getLoyaltyAccount(userId).catch(() => null) : null,
    loyaltyService.getActiveLoyaltyRule().catch(() => ({})),
  ]);

  let coupon = null;
  let userCouponRedemptions = 0;
  if (couponCode?.trim()) {
    coupon = await couponService.getCouponByCode(couponCode).catch(() => null);
    if (coupon && userId) {
      userCouponRedemptions = await couponService.getUserCouponRedemptionCount(coupon.id, userId);
    }
  }

  let giftCardBalance = 0;
  if (giftCardCode?.trim()) {
    const card = await giftCardService.lookupGiftCard(giftCardCode).catch(() => null);
    if (card?.status === 'active') giftCardBalance = card.balance;
  }

  const preview = previewCheckoutRewards({
    lines: cartLines,
    promotions,
    coupon,
    userCouponRedemptions,
    loyaltyPointsToRedeem,
    loyaltyBalance: loyaltyAccount?.pointsBalance || 0,
    loyaltyRules: loyaltyRule || {},
    giftCardBalance,
    giftCardAmount,
    deliveryType,
    deliveryFee: DELIVERY_FEE,
  });

  return {
    ...preview,
    loyaltyBalance: loyaltyAccount?.pointsBalance || 0,
    referralCode: loyaltyAccount?.referralCode || null,
    coupon,
  };
}

/**
 * Shape reward fields for place_order RPC.
 */
export function toPlaceOrderRewardParams(preview, {
  couponCode,
  giftCardCode,
} = {}) {
  return {
    couponCode: preview.couponValid ? (couponCode || null) : null,
    loyaltyPoints: preview.loyaltyPoints || 0,
    giftCardCode: preview.giftCardAmount > 0 ? (giftCardCode || null) : null,
    giftCardAmount: preview.giftCardAmount || 0,
    discountAmount: Math.max(
      0,
      (preview.merchandiseDiscount || 0) - (preview.loyaltyDiscount || 0),
    ) + (preview.loyaltyDiscount || 0),
    // Server adds loyalty value again from points — send merchandise-only discount
    // excluding loyalty so we don't double-count. Prefer:
    freeDelivery: Boolean(preview.freeDelivery),
    promotionsApplied: preview.applied || [],
  };
}

/**
 * Correct RPC payload: discount_amount should be promo+coupon only;
 * loyalty is applied via p_loyalty_points on the server.
 */
export function buildPlaceOrderRewardPayload(preview, inputs = {}) {
  const promoAndCouponDiscount = Math.max(
    0,
    round2((preview.merchandiseDiscount || 0) - (preview.loyaltyDiscount || 0)),
  );

  return {
    p_coupon_code: preview.couponValid ? (inputs.couponCode || null) : null,
    p_loyalty_points: preview.loyaltyPoints || 0,
    p_gift_card_code: preview.giftCardAmount > 0 ? (inputs.giftCardCode || null) : null,
    p_gift_card_amount: preview.giftCardAmount || 0,
    p_discount_amount: promoAndCouponDiscount,
    p_free_delivery: Boolean(preview.freeDelivery),
    p_promotions_applied: preview.applied || [],
    p_referral_code: inputs.referralCode || null,
  };
}

function round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

export const checkoutRewardsService = {
  buildCheckoutRewardPreview,
  buildPlaceOrderRewardPayload,
  toPlaceOrderRewardParams,
};
