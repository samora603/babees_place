import { supabase } from '@/lib/supabaseClient';
import { mapPromotion } from '@/models/rewards';
import { applyPromotions, computePromotionDiscount } from '@/services/rewardEngine';
import { auditService, AUDIT_ACTIONS } from '@/services/auditService';

export async function listActivePromotions() {
  const { data, error } = await supabase
    .from('promotions')
    .select('*')
    .eq('status', 'active')
    .order('priority', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapPromotion);
}

export async function listAllPromotions() {
  const { data, error } = await supabase
    .from('promotions')
    .select('*')
    .order('priority', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapPromotion);
}

export async function getPromotion(id) {
  const { data, error } = await supabase.from('promotions').select('*').eq('id', id).maybeSingle();
  if (error) throw error;
  return mapPromotion(data);
}

export async function upsertPromotion(payload) {
  const row = {
    id: payload.id,
    code: payload.code || null,
    name: payload.name,
    description: payload.description || null,
    promo_type: payload.promoType,
    status: payload.status || 'draft',
    priority: payload.priority ?? 100,
    stackable: Boolean(payload.stackable),
    percent_off: payload.percentOff ?? null,
    amount_off: payload.amountOff ?? null,
    buy_quantity: payload.buyQuantity ?? null,
    get_quantity: payload.getQuantity ?? null,
    category_id: payload.categoryId || null,
    product_id: payload.productId || null,
    min_order_amount: payload.minOrderAmount ?? 0,
    max_discount_amount: payload.maxDiscountAmount ?? null,
    usage_limit: payload.usageLimit ?? null,
    per_user_limit: payload.perUserLimit ?? null,
    starts_at: payload.startsAt || null,
    ends_at: payload.endsAt || null,
  };
  const { data, error } = await supabase.from('promotions').upsert(row).select().single();
  if (error) throw error;
  auditService.writeAuditSafe({
    action: AUDIT_ACTIONS.PROMOTION_CHANGED,
    entityType: 'promotion',
    entityId: data.id,
    summary: data.name,
  });
  return mapPromotion(data);
}

export async function deletePromotion(id) {
  const { error } = await supabase.from('promotions').delete().eq('id', id);
  if (error) throw error;
  return { success: true };
}

export function evaluatePromotionsForCart(promotions, lines) {
  return applyPromotions(promotions, lines);
}

export function evaluateSinglePromotion(promo, lines) {
  return computePromotionDiscount(promo, lines);
}

export const promotionService = {
  listActivePromotions,
  listAllPromotions,
  getPromotion,
  upsertPromotion,
  deletePromotion,
  evaluatePromotionsForCart,
  evaluateSinglePromotion,
};
