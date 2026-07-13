import { supabase } from '@/lib/supabaseClient';
import { mapReferral } from '@/models/rewards';
import { ensureLoyaltyAccount } from '@/services/loyaltyService';

const REFERRER_BONUS = 200;
const REFERRED_BONUS = 100;

export async function getMyReferralCode(userId) {
  const account = await ensureLoyaltyAccount(userId);
  return account?.referralCode || null;
}

export async function attachReferralOnSignup({ referredUserId, referralCode }) {
  if (!referralCode?.trim() || !referredUserId) return null;

  const code = referralCode.trim().toUpperCase();
  const { data: referrer } = await supabase
    .from('loyalty_accounts')
    .select('*')
    .eq('referral_code', code)
    .maybeSingle();

  if (!referrer || referrer.user_id === referredUserId) return null;

  const { data, error } = await supabase
    .from('referrals')
    .insert({
      referrer_user_id: referrer.user_id,
      referred_user_id: referredUserId,
      referral_code: code,
      status: 'signed_up',
      reward_points: REFERRER_BONUS,
      referred_reward_points: REFERRED_BONUS,
    })
    .select()
    .single();

  if (error) {
    // Unique referred user — already attached
    console.warn('attachReferralOnSignup:', error.message);
    return null;
  }
  return mapReferral(data);
}

/**
 * Qualify referral after first successful order and credit points.
 */
export async function qualifyReferralForOrder({ orderId, userId }) {
  const { data: referral } = await supabase
    .from('referrals')
    .select('*')
    .eq('referred_user_id', userId)
    .in('status', ['signed_up', 'pending'])
    .maybeSingle();

  if (!referral) return null;

  const { data: updated, error } = await supabase
    .from('referrals')
    .update({
      status: 'rewarded',
      order_id: orderId,
      rewarded_at: new Date().toISOString(),
    })
    .eq('id', referral.id)
    .select()
    .single();

  if (error) throw error;

  await creditReferralBonus(referral.referrer_user_id, referral.reward_points || REFERRER_BONUS, orderId, 'Referrer bonus');
  await creditReferralBonus(userId, referral.referred_reward_points || REFERRED_BONUS, orderId, 'Welcome referral bonus');

  return mapReferral(updated);
}

async function creditReferralBonus(userId, points, orderId, description) {
  if (!points || points <= 0) return;
  await ensureLoyaltyAccount(userId);
  const { data: account } = await supabase
    .from('loyalty_accounts')
    .select('*')
    .eq('user_id', userId)
    .single();

  const balance = (account?.points_balance || 0) + points;
  await supabase
    .from('loyalty_accounts')
    .update({
      points_balance: balance,
      lifetime_earned: (account?.lifetime_earned || 0) + points,
    })
    .eq('user_id', userId);

  await supabase.from('loyalty_transactions').insert({
    user_id: userId,
    tx_type: 'earn_referral',
    points,
    balance_after: balance,
    order_id: orderId,
    description,
  });
}

export async function listMyReferrals(userId) {
  const { data, error } = await supabase
    .from('referrals')
    .select('*')
    .eq('referrer_user_id', userId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapReferral);
}

export async function listAllReferrals() {
  const { data, error } = await supabase
    .from('referrals')
    .select('*')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return (data || []).map(mapReferral);
}

export async function getReferralStats(userId) {
  const referrals = await listMyReferrals(userId);
  const account = await ensureLoyaltyAccount(userId);
  return {
    total: referrals.length,
    rewarded: referrals.filter((r) => r.status === 'rewarded').length,
    pending: referrals.filter((r) => r.status !== 'rewarded' && r.status !== 'cancelled').length,
    account,
  };
}

export const referralService = {
  getMyReferralCode,
  attachReferralOnSignup,
  qualifyReferralForOrder,
  listMyReferrals,
  listAllReferrals,
  getReferralStats,
  REFERRER_BONUS,
  REFERRED_BONUS,
};
