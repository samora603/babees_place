/**
 * Generic promotion / checkout reward engine (Workstream 8).
 * Pure functions — no React, no Supabase. Services call this for previews.
 */

/** @typedef {{ id: string, productId: string, categoryId?: string|null, price: number, quantity: number, name?: string }} CartLine */
/** @typedef {{
 *  id: string, code?: string|null, name: string, promoType: string,
 *  priority?: number, stackable?: boolean, percentOff?: number|null,
 *  amountOff?: number|null, buyQuantity?: number|null, getQuantity?: number|null,
 *  categoryId?: string|null, productId?: string|null, minOrderAmount?: number,
 *  maxDiscountAmount?: number|null, startsAt?: string|null, endsAt?: string|null,
 *  status?: string, usageLimit?: number|null, usageCount?: number,
 * }} Promotion */
/** @typedef {{
 *  id: string, code: string, discountType: string, percentOff?: number|null,
 *  amountOff?: number|null, freeDelivery?: boolean, minOrderAmount?: number,
 *  maxDiscountAmount?: number|null, usageLimit?: number|null, usageCount?: number,
 *  perUserLimit?: number|null, isOneTime?: boolean, isActive?: boolean,
 *  startsAt?: string|null, endsAt?: string|null, userRedemptionCount?: number,
 * }} Coupon */

export function cartSubtotal(lines = []) {
  return round2(lines.reduce((sum, l) => sum + Number(l.price || 0) * Number(l.quantity || 0), 0));
}

export function round2(n) {
  return Math.round((Number(n) || 0) * 100) / 100;
}

export function isWithinDateRange(now, startsAt, endsAt) {
  const t = now instanceof Date ? now.getTime() : new Date(now).getTime();
  if (startsAt && new Date(startsAt).getTime() > t) return false;
  if (endsAt && new Date(endsAt).getTime() < t) return false;
  return true;
}

/**
 * Validate coupon against cart context.
 * @returns {{ valid: boolean, errors: string[], coupon?: Coupon, discount: number, freeDelivery: boolean }}
 */
export function validateCoupon(coupon, { subtotal, userRedemptionCount = 0, now = new Date() } = {}) {
  const errors = [];
  if (!coupon) return { valid: false, errors: ['Coupon not found'], discount: 0, freeDelivery: false };
  if (coupon.isActive === false) errors.push('Coupon is inactive');
  if (!isWithinDateRange(now, coupon.startsAt, coupon.endsAt)) errors.push('Coupon is outside its valid dates');
  if (coupon.usageLimit != null && coupon.usageCount >= coupon.usageLimit) errors.push('Coupon usage limit reached');
  if (coupon.perUserLimit != null && userRedemptionCount >= coupon.perUserLimit) {
    errors.push('You have already used this coupon');
  }
  if (coupon.isOneTime && userRedemptionCount > 0) errors.push('This one-time coupon was already used');
  if (subtotal < (coupon.minOrderAmount || 0)) {
    errors.push(`Minimum order of ${coupon.minOrderAmount} required`);
  }

  if (errors.length) {
    return { valid: false, errors, discount: 0, freeDelivery: false };
  }

  let discount = 0;
  let freeDelivery = Boolean(coupon.freeDelivery) || coupon.discountType === 'free_delivery';

  if (coupon.discountType === 'percentage') {
    discount = round2(subtotal * (Number(coupon.percentOff) || 0) / 100);
  } else if (coupon.discountType === 'fixed') {
    discount = round2(Number(coupon.amountOff) || 0);
  }

  if (coupon.maxDiscountAmount != null) {
    discount = Math.min(discount, Number(coupon.maxDiscountAmount));
  }
  discount = Math.min(discount, subtotal);

  return { valid: true, errors: [], coupon, discount, freeDelivery };
}

/**
 * Compute discount for a single promotion against cart lines.
 */
export function computePromotionDiscount(promo, lines = [], { now = new Date() } = {}) {
  if (!promo || promo.status === 'paused' || promo.status === 'expired' || promo.status === 'draft') {
    return { discount: 0, freeDelivery: false, applicable: false, reason: 'inactive' };
  }
  if (!isWithinDateRange(now, promo.startsAt, promo.endsAt)) {
    return { discount: 0, freeDelivery: false, applicable: false, reason: 'date' };
  }

  const subtotal = cartSubtotal(lines);
  if (subtotal < (promo.minOrderAmount || 0)) {
    return { discount: 0, freeDelivery: false, applicable: false, reason: 'min_order' };
  }
  if (promo.usageLimit != null && promo.usageCount >= promo.usageLimit) {
    return { discount: 0, freeDelivery: false, applicable: false, reason: 'usage_limit' };
  }

  const type = promo.promoType;
  let discount = 0;
  let freeDelivery = false;
  let eligibleSubtotal = subtotal;

  if (type === 'category' && promo.categoryId) {
    eligibleSubtotal = cartSubtotal(lines.filter((l) => l.categoryId === promo.categoryId));
  } else if (type === 'product' && promo.productId) {
    eligibleSubtotal = cartSubtotal(lines.filter((l) => l.productId === promo.productId));
  }

  if (type === 'free_delivery') {
    freeDelivery = true;
  } else if (type === 'percentage' || type === 'storewide' || type === 'category' || type === 'product') {
    const pct = Number(promo.percentOff) || 0;
    discount = round2(eligibleSubtotal * pct / 100);
  } else if (type === 'fixed') {
    discount = round2(Number(promo.amountOff) || 0);
  } else if (type === 'buy_x_get_y') {
    const buy = Number(promo.buyQuantity) || 0;
    const get = Number(promo.getQuantity) || 0;
    if (buy > 0 && get > 0) {
      const targetLines = promo.productId
        ? lines.filter((l) => l.productId === promo.productId)
        : lines;
      const qty = targetLines.reduce((s, l) => s + Number(l.quantity || 0), 0);
      const sets = Math.floor(qty / (buy + get));
      if (sets > 0) {
        const unit = Math.min(...targetLines.map((l) => Number(l.price) || 0));
        discount = round2(sets * get * unit);
      }
    }
  }

  if (promo.maxDiscountAmount != null) {
    discount = Math.min(discount, Number(promo.maxDiscountAmount));
  }
  discount = Math.min(discount, subtotal);

  const applicable = discount > 0 || freeDelivery;
  return { discount, freeDelivery, applicable, reason: applicable ? null : 'no_benefit' };
}

/**
 * Apply promotions with priority + stacking rules.
 * Non-stackable promos: only the highest-priority applicable one (plus stackables).
 */
export function applyPromotions(promotions = [], lines = [], opts = {}) {
  const sorted = [...promotions].sort((a, b) => (b.priority || 0) - (a.priority || 0));
  const applied = [];
  let merchandiseDiscount = 0;
  let freeDelivery = false;
  let usedNonStackable = false;

  for (const promo of sorted) {
    if (!promo.stackable && usedNonStackable) continue;

    const result = computePromotionDiscount(promo, lines, opts);
    if (!result.applicable) continue;

    if (!promo.stackable) {
      if (usedNonStackable) continue;
      usedNonStackable = true;
    }

    merchandiseDiscount = round2(merchandiseDiscount + result.discount);
    if (result.freeDelivery) freeDelivery = true;
    applied.push({
      id: promo.id,
      code: promo.code,
      name: promo.name,
      promoType: promo.promoType,
      discount: result.discount,
      freeDelivery: result.freeDelivery,
    });
  }

  const subtotal = cartSubtotal(lines);
  merchandiseDiscount = Math.min(merchandiseDiscount, subtotal);

  return {
    applied,
    merchandiseDiscount,
    freeDelivery,
    subtotal,
  };
}

/**
 * Loyalty points → currency discount.
 */
export function calculateLoyaltyRedemption(points, {
  balance = 0,
  redeemPointsPerCurrency = 10,
  minRedeemPoints = 100,
  maxRedeemPercent = 50,
  subtotal = 0,
} = {}) {
  const requested = Math.max(0, Math.floor(Number(points) || 0));
  if (requested <= 0) {
    return { points: 0, discount: 0, errors: [] };
  }
  const errors = [];
  if (requested > balance) errors.push('Insufficient points balance');
  if (requested < minRedeemPoints) errors.push(`Minimum ${minRedeemPoints} points required`);

  let discount = round2(requested / (redeemPointsPerCurrency || 10));
  const maxByPercent = round2(subtotal * (maxRedeemPercent || 50) / 100);
  if (discount > maxByPercent) {
    discount = maxByPercent;
  }
  if (discount > subtotal) discount = subtotal;

  // Adjust points to match capped discount
  const adjustedPoints = Math.min(requested, Math.ceil(discount * (redeemPointsPerCurrency || 10)));

  return {
    points: errors.length ? 0 : adjustedPoints,
    discount: errors.length ? 0 : discount,
    errors,
  };
}

export function calculateEarnPoints(orderTotal, earnPointsPerCurrency = 0.01) {
  return Math.max(0, Math.floor(Number(orderTotal || 0) * Number(earnPointsPerCurrency || 0)));
}

/**
 * Gift card partial redemption against payable total.
 */
export function calculateGiftCardRedemption(balance, requestedAmount, payableTotal) {
  const bal = Number(balance) || 0;
  const req = Number(requestedAmount);
  const payable = Math.max(0, Number(payableTotal) || 0);
  if (bal <= 0 || payable <= 0) {
    return { amount: 0, errors: bal <= 0 ? ['Gift card has no balance'] : [] };
  }
  const amount = round2(Math.min(
    bal,
    Number.isFinite(req) && req > 0 ? req : payable,
    payable,
  ));
  return { amount, errors: [] };
}

/**
 * Full checkout reward preview.
 *
 * Order of application:
 * 1. Automatic promotions (priority/stacking)
 * 2. Coupon (replaces or adds per stackable — coupon adds on top unless free_delivery only)
 * 3. Loyalty points against remaining merchandise
 * 4. Free delivery from promo/coupon
 * 5. Gift card against payable total
 */
export function previewCheckoutRewards({
  lines = [],
  promotions = [],
  coupon = null,
  userCouponRedemptions = 0,
  loyaltyPointsToRedeem = 0,
  loyaltyBalance = 0,
  loyaltyRules = {},
  giftCardBalance = 0,
  giftCardAmount = null,
  deliveryType = 'pickup',
  deliveryFee = 200,
  now = new Date(),
} = {}) {
  const promoResult = applyPromotions(promotions, lines, { now });
  let merchandiseDiscount = promoResult.merchandiseDiscount;
  let freeDelivery = promoResult.freeDelivery;
  const applied = [...promoResult.applied];

  let couponResult = null;
  if (coupon) {
    couponResult = validateCoupon(coupon, {
      subtotal: promoResult.subtotal,
      userRedemptionCount: userCouponRedemptions,
      now,
    });
    if (couponResult.valid) {
      merchandiseDiscount = round2(merchandiseDiscount + couponResult.discount);
      if (couponResult.freeDelivery) freeDelivery = true;
      applied.push({
        id: coupon.id,
        code: coupon.code,
        name: coupon.name || coupon.code,
        promoType: 'coupon',
        discount: couponResult.discount,
        freeDelivery: couponResult.freeDelivery,
      });
    }
  }

  merchandiseDiscount = Math.min(merchandiseDiscount, promoResult.subtotal);
  const afterPromo = round2(Math.max(promoResult.subtotal - merchandiseDiscount, 0));

  const loyalty = calculateLoyaltyRedemption(loyaltyPointsToRedeem, {
    balance: loyaltyBalance,
    redeemPointsPerCurrency: loyaltyRules.redeemPointsPerCurrency ?? 10,
    minRedeemPoints: loyaltyRules.minRedeemPoints ?? 100,
    maxRedeemPercent: loyaltyRules.maxRedeemPercent ?? 50,
    subtotal: afterPromo,
  });

  merchandiseDiscount = round2(merchandiseDiscount + loyalty.discount);
  const merchandisePayable = round2(Math.max(promoResult.subtotal - merchandiseDiscount, 0));

  const fee = deliveryType === 'delivery'
    ? (freeDelivery ? 0 : deliveryFee)
    : 0;

  let payable = round2(merchandisePayable + fee);

  const gift = calculateGiftCardRedemption(giftCardBalance, giftCardAmount, payable);
  payable = round2(Math.max(payable - gift.amount, 0));

  const savings = round2(
    (deliveryType === 'delivery' && freeDelivery ? deliveryFee : 0)
    + merchandiseDiscount
    + gift.amount,
  );

  return {
    subtotal: promoResult.subtotal,
    merchandiseDiscount,
    loyaltyPoints: loyalty.points,
    loyaltyDiscount: loyalty.discount,
    loyaltyErrors: loyalty.errors,
    couponValid: couponResult ? couponResult.valid : null,
    couponErrors: couponResult?.errors || [],
    freeDelivery,
    deliveryFee: fee,
    giftCardAmount: gift.amount,
    giftCardErrors: gift.errors,
    total: payable,
    savings,
    applied,
    promotionsApplied: applied,
  };
}

export const rewardEngine = {
  cartSubtotal,
  round2,
  isWithinDateRange,
  validateCoupon,
  computePromotionDiscount,
  applyPromotions,
  calculateLoyaltyRedemption,
  calculateEarnPoints,
  calculateGiftCardRedemption,
  previewCheckoutRewards,
};
