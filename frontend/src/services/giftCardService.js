import { supabase } from '@/lib/supabaseClient';
import { mapGiftCard } from '@/models/rewards';
import { calculateGiftCardRedemption, isWithinDateRange } from '@/services/rewardEngine';
import { auditService, AUDIT_ACTIONS } from '@/services/auditService';

export async function lookupGiftCard(code) {
  if (!code?.trim()) return null;
  const { data, error } = await supabase.rpc('lookup_gift_card', {
    p_code: code.trim(),
  });
  if (error) throw error;
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) return null;
  return {
    id: row.id,
    code: row.code,
    balance: Number(row.balance),
    status: row.status,
    expiresAt: row.expires_at,
    currency: row.currency || 'KES',
  };
}

export async function validateGiftCardForCheckout(code, { payableTotal, amount = null }) {
  const card = await lookupGiftCard(code);
  if (!card) return { valid: false, errors: ['Gift card not found'], amount: 0 };
  if (card.status !== 'active') return { valid: false, errors: ['Gift card is not active'], amount: 0, card };
  if (card.expiresAt && !isWithinDateRange(new Date(), null, card.expiresAt)) {
    return { valid: false, errors: ['Gift card has expired'], amount: 0, card };
  }
  const redemption = calculateGiftCardRedemption(card.balance, amount, payableTotal);
  if (redemption.errors.length) {
    return { valid: false, errors: redemption.errors, amount: 0, card };
  }
  return { valid: true, errors: [], amount: redemption.amount, card };
}

export async function listGiftCards() {
  const { data, error } = await supabase
    .from('gift_cards')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapGiftCard);
}

export async function createGiftCard(payload) {
  const balance = Number(payload.initialBalance || payload.balance || 0);
  const code = (payload.code || `GIFT${Date.now().toString(36).toUpperCase()}`).toUpperCase();
  const row = {
    code,
    initial_balance: balance,
    balance,
    currency: payload.currency || 'KES',
    status: 'active',
    purchased_by: payload.purchasedBy || null,
    recipient_email: payload.recipientEmail || null,
    expires_at: payload.expiresAt || null,
  };
  const { data, error } = await supabase.from('gift_cards').insert(row).select().single();
  if (error) throw error;

  await supabase.from('gift_card_transactions').insert({
    gift_card_id: data.id,
    user_id: payload.purchasedBy || null,
    tx_type: 'issue',
    amount: balance,
    balance_after: balance,
  });

  auditService.writeAuditSafe({
    action: AUDIT_ACTIONS.GIFT_CARD_ISSUED,
    entityType: 'gift_card',
    entityId: data.id,
    summary: data.code,
    metadata: { balance },
  });

  return mapGiftCard(data);
}

export async function updateGiftCardStatus(id, status) {
  const { data, error } = await supabase
    .from('gift_cards')
    .update({ status })
    .eq('id', id)
    .select()
    .single();
  if (error) throw error;
  return mapGiftCard(data);
}

export const giftCardService = {
  lookupGiftCard,
  validateGiftCardForCheckout,
  listGiftCards,
  createGiftCard,
  updateGiftCardStatus,
};
