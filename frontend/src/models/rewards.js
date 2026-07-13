/** Domain mappers for promotions / loyalty (WS8). */

export function mapPromotion(row) {
  if (!row) return null;
  return {
    id: row.id,
    code: row.code || null,
    name: row.name,
    description: row.description || null,
    promoType: row.promo_type,
    status: row.status,
    priority: row.priority ?? 100,
    stackable: Boolean(row.stackable),
    percentOff: row.percent_off != null ? Number(row.percent_off) : null,
    amountOff: row.amount_off != null ? Number(row.amount_off) : null,
    buyQuantity: row.buy_quantity,
    getQuantity: row.get_quantity,
    categoryId: row.category_id || null,
    productId: row.product_id || null,
    minOrderAmount: Number(row.min_order_amount || 0),
    maxDiscountAmount: row.max_discount_amount != null ? Number(row.max_discount_amount) : null,
    usageLimit: row.usage_limit,
    usageCount: row.usage_count ?? 0,
    perUserLimit: row.per_user_limit,
    startsAt: row.starts_at || null,
    endsAt: row.ends_at || null,
    eligibility: row.eligibility || {},
    metadata: row.metadata || {},
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapCoupon(row) {
  if (!row) return null;
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    description: row.description || null,
    discountType: row.discount_type,
    percentOff: row.percent_off != null ? Number(row.percent_off) : null,
    amountOff: row.amount_off != null ? Number(row.amount_off) : null,
    freeDelivery: Boolean(row.free_delivery),
    minOrderAmount: Number(row.min_order_amount || 0),
    maxDiscountAmount: row.max_discount_amount != null ? Number(row.max_discount_amount) : null,
    usageLimit: row.usage_limit,
    usageCount: row.usage_count ?? 0,
    perUserLimit: row.per_user_limit,
    isOneTime: Boolean(row.is_one_time),
    isActive: row.is_active !== false,
    startsAt: row.starts_at || null,
    endsAt: row.ends_at || null,
    promotionId: row.promotion_id || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapLoyaltyAccount(row) {
  if (!row) return null;
  return {
    userId: row.user_id,
    pointsBalance: row.points_balance ?? 0,
    lifetimeEarned: row.lifetime_earned ?? 0,
    lifetimeRedeemed: row.lifetime_redeemed ?? 0,
    referralCode: row.referral_code,
    tier: row.tier || 'member',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapLoyaltyRule(row) {
  if (!row) return null;
  return {
    id: row.id,
    code: row.code,
    name: row.name,
    isActive: row.is_active !== false,
    earnPointsPerCurrency: Number(row.earn_points_per_currency ?? 0.01),
    redeemPointsPerCurrency: Number(row.redeem_points_per_currency ?? 10),
    freeDeliveryPoints: row.free_delivery_points ?? 500,
    minRedeemPoints: row.min_redeem_points ?? 100,
    maxRedeemPercent: Number(row.max_redeem_percent ?? 50),
    metadata: row.metadata || {},
  };
}

export function mapGiftCard(row) {
  if (!row) return null;
  return {
    id: row.id,
    code: row.code,
    initialBalance: Number(row.initial_balance),
    balance: Number(row.balance),
    currency: row.currency || 'KES',
    status: row.status,
    purchasedBy: row.purchased_by || null,
    recipientEmail: row.recipient_email || null,
    expiresAt: row.expires_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapReferral(row) {
  if (!row) return null;
  return {
    id: row.id,
    referrerUserId: row.referrer_user_id,
    referredUserId: row.referred_user_id,
    referralCode: row.referral_code,
    status: row.status,
    rewardPoints: row.reward_points ?? 0,
    referredRewardPoints: row.referred_reward_points ?? 0,
    orderId: row.order_id || null,
    rewardedAt: row.rewarded_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

export function mapLoyaltyTransaction(row) {
  if (!row) return null;
  return {
    id: row.id,
    userId: row.user_id,
    txType: row.tx_type,
    points: row.points,
    balanceAfter: row.balance_after,
    orderId: row.order_id || null,
    description: row.description || null,
    metadata: row.metadata || {},
    createdAt: row.created_at,
  };
}
