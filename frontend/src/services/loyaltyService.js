import { supabase } from '@/lib/supabaseClient';
import {
  mapLoyaltyAccount,
  mapLoyaltyRule,
  mapLoyaltyTransaction,
} from '@/models/rewards';
import { calculateEarnPoints, calculateLoyaltyRedemption } from '@/services/rewardEngine';
import { auditService, AUDIT_ACTIONS } from '@/services/auditService';

export async function ensureLoyaltyAccount(userId = null) {
  const { data, error } = await supabase.rpc('ensure_loyalty_account', {
    p_user_id: userId || undefined,
  });
  if (error) throw error;
  return mapLoyaltyAccount(data);
}

export async function getLoyaltyAccount(userId) {
  try {
    return await ensureLoyaltyAccount(userId);
  } catch {
    const { data, error } = await supabase
      .from('loyalty_accounts')
      .select('*')
      .eq('user_id', userId)
      .maybeSingle();
    if (error) throw error;
    return mapLoyaltyAccount(data);
  }
}

export async function getActiveLoyaltyRule() {
  const { data, error } = await supabase
    .from('loyalty_rules')
    .select('*')
    .eq('is_active', true)
    .order('created_at', { ascending: true })
    .limit(1)
    .maybeSingle();
  if (error) throw error;
  return mapLoyaltyRule(data) || {
    earnPointsPerCurrency: 0.01,
    redeemPointsPerCurrency: 10,
    freeDeliveryPoints: 500,
    minRedeemPoints: 100,
    maxRedeemPercent: 50,
  };
}

export async function upsertLoyaltyRule(payload) {
  const row = {
    id: payload.id,
    code: payload.code || 'default',
    name: payload.name || 'Loyalty rules',
    is_active: payload.isActive !== false,
    earn_points_per_currency: payload.earnPointsPerCurrency ?? 0.01,
    redeem_points_per_currency: payload.redeemPointsPerCurrency ?? 10,
    free_delivery_points: payload.freeDeliveryPoints ?? 500,
    min_redeem_points: payload.minRedeemPoints ?? 100,
    max_redeem_percent: payload.maxRedeemPercent ?? 50,
  };
  const { data, error } = await supabase.from('loyalty_rules').upsert(row).select().single();
  if (error) throw error;
  auditService.writeAuditSafe({
    action: AUDIT_ACTIONS.LOYALTY_RULES_UPDATED,
    entityType: 'loyalty_rule',
    entityId: data.id,
    summary: data.name,
  });
  return mapLoyaltyRule(data);
}

export async function listLoyaltyTransactions(userId, { limit = 20 } = {}) {
  const { data, error } = await supabase
    .from('loyalty_transactions')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) throw error;
  return (data || []).map(mapLoyaltyTransaction);
}

export function previewRedeemPoints(points, context) {
  return calculateLoyaltyRedemption(points, context);
}

export function previewEarnPoints(orderTotal, rule) {
  return calculateEarnPoints(orderTotal, rule?.earnPointsPerCurrency);
}

export async function awardPointsForOrder(orderId) {
  const { data, error } = await supabase.rpc('award_loyalty_for_order', {
    p_order_id: orderId,
  });
  if (error) {
    console.warn('award_loyalty_for_order:', error.message);
    return 0;
  }
  return data || 0;
}

export const loyaltyService = {
  ensureLoyaltyAccount,
  getLoyaltyAccount,
  getActiveLoyaltyRule,
  upsertLoyaltyRule,
  listLoyaltyTransactions,
  previewRedeemPoints,
  previewEarnPoints,
  awardPointsForOrder,
};
