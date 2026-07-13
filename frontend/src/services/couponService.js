import { supabase } from '@/lib/supabaseClient';
import { mapCoupon } from '@/models/rewards';
import { validateCoupon } from '@/services/rewardEngine';
import { auditService, AUDIT_ACTIONS } from '@/services/auditService';

export async function listCoupons({ activeOnly = false } = {}) {
  let query = supabase.from('coupons').select('*').order('created_at', { ascending: false });
  if (activeOnly) query = query.eq('is_active', true);
  const { data, error } = await query;
  if (error) throw error;
  return (data || []).map(mapCoupon);
}

export async function getCouponByCode(code) {
  if (!code?.trim()) return null;
  const { data, error } = await supabase
    .from('coupons')
    .select('*')
    .ilike('code', code.trim())
    .maybeSingle();
  if (error) throw error;
  return mapCoupon(data);
}

export async function getUserCouponRedemptionCount(couponId, userId) {
  const { count, error } = await supabase
    .from('coupon_redemptions')
    .select('id', { count: 'exact', head: true })
    .eq('coupon_id', couponId)
    .eq('user_id', userId);
  if (error) return 0;
  return count || 0;
}

/**
 * Fetch + validate coupon for checkout.
 */
export async function validateCouponForCheckout(code, { subtotal, userId }) {
  const coupon = await getCouponByCode(code);
  if (!coupon) {
    return { valid: false, errors: ['Coupon not found'], discount: 0, freeDelivery: false };
  }
  let userRedemptionCount = 0;
  if (userId && coupon.id) {
    userRedemptionCount = await getUserCouponRedemptionCount(coupon.id, userId);
  }
  return {
    ...validateCoupon(coupon, { subtotal, userRedemptionCount }),
    coupon,
  };
}

export async function upsertCoupon(payload) {
  const row = {
    id: payload.id,
    code: String(payload.code || '').trim().toUpperCase(),
    name: payload.name,
    description: payload.description || null,
    discount_type: payload.discountType,
    percent_off: payload.percentOff ?? null,
    amount_off: payload.amountOff ?? null,
    free_delivery: Boolean(payload.freeDelivery) || payload.discountType === 'free_delivery',
    min_order_amount: payload.minOrderAmount ?? 0,
    max_discount_amount: payload.maxDiscountAmount ?? null,
    usage_limit: payload.usageLimit ?? null,
    per_user_limit: payload.perUserLimit ?? 1,
    is_one_time: Boolean(payload.isOneTime),
    is_active: payload.isActive !== false,
    starts_at: payload.startsAt || null,
    ends_at: payload.endsAt || null,
  };
  const { data, error } = await supabase.from('coupons').upsert(row).select().single();
  if (error) throw error;
  auditService.writeAuditSafe({
    action: payload.id ? AUDIT_ACTIONS.COUPON_UPDATED : AUDIT_ACTIONS.COUPON_CREATED,
    entityType: 'coupon',
    entityId: data.id,
    summary: data.code,
  });
  return mapCoupon(data);
}

export async function deleteCoupon(id) {
  const { error } = await supabase.from('coupons').delete().eq('id', id);
  if (error) throw error;
  return { success: true };
}

export async function listMyAvailableCoupons(userId) {
  const coupons = await listCoupons({ activeOnly: true });
  const available = [];
  for (const c of coupons) {
    const used = userId ? await getUserCouponRedemptionCount(c.id, userId) : 0;
    const check = validateCoupon(c, { subtotal: 999999, userRedemptionCount: used });
    if (check.valid) available.push({ ...c, userRedemptionCount: used });
  }
  return available;
}

export const couponService = {
  listCoupons,
  getCouponByCode,
  getUserCouponRedemptionCount,
  validateCouponForCheckout,
  upsertCoupon,
  deleteCoupon,
  listMyAvailableCoupons,
};
