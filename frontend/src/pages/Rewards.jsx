import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/context/AuthContext';
import { loyaltyService } from '@/services/loyaltyService';
import { couponService } from '@/services/couponService';
import { referralService } from '@/services/referralService';
import { giftCardService } from '@/services/giftCardService';
import { formatCurrency } from '@/utils/helpers';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

export default function Rewards() {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [account, setAccount] = useState(null);
  const [transactions, setTransactions] = useState([]);
  const [coupons, setCoupons] = useState([]);
  const [referrals, setReferrals] = useState([]);
  const [giftLookup, setGiftLookup] = useState('');
  const [giftCard, setGiftCard] = useState(null);

  useEffect(() => {
    if (!user?.id) return undefined;
    let mounted = true;
    (async () => {
      setLoading(true);
      try {
        const [acc, txs, coups, refs] = await Promise.all([
          loyaltyService.getLoyaltyAccount(user.id),
          loyaltyService.listLoyaltyTransactions(user.id, { limit: 10 }),
          couponService.listMyAvailableCoupons(user.id).catch(() => []),
          referralService.listMyReferrals(user.id).catch(() => []),
        ]);
        if (!mounted) return;
        setAccount(acc);
        setTransactions(txs);
        setCoupons(coups);
        setReferrals(refs);
      } catch (err) {
        toast.error(err.message || 'Could not load rewards');
      } finally {
        if (mounted) setLoading(false);
      }
    })();
    return () => { mounted = false; };
  }, [user?.id]);

  const handleGiftLookup = async (e) => {
    e.preventDefault();
    try {
      const card = await giftCardService.lookupGiftCard(giftLookup);
      setGiftCard(card);
      if (!card) toast.error('Gift card not found');
    } catch (err) {
      toast.error(err.message || 'Lookup failed');
    }
  };

  const copyReferral = async () => {
    if (!account?.referralCode) return;
    await navigator.clipboard.writeText(account.referralCode);
    toast.success('Referral code copied');
  };

  if (loading) {
    return (
      <div className="min-h-[50vh] flex items-center justify-center">
        <Spinner size="lg" />
      </div>
    );
  }

  return (
    <div className="section-container py-10 max-w-3xl space-y-8">
      <div>
        <h1 className="font-display font-bold text-3xl mb-2">Rewards</h1>
        <p className="text-slate-400 text-sm">
          Points, coupons, referrals, and gift cards.
        </p>
      </div>

      <section className="card p-6">
        <h2 className="font-display font-semibold text-xl text-white mb-2">Points balance</h2>
        <p className="font-display text-4xl text-brand-400">{account?.pointsBalance ?? 0}</p>
        <p className="text-xs text-slate-500 mt-2">
          Lifetime earned {account?.lifetimeEarned ?? 0} · Redeemed {account?.lifetimeRedeemed ?? 0}
          · Tier {account?.tier || 'member'}
        </p>
      </section>

      <section className="card p-6 space-y-3">
        <h2 className="font-display font-semibold text-xl text-white">Your referral code</h2>
        <div className="flex items-center gap-3">
          <code className="text-brand-400 text-lg tracking-widest">{account?.referralCode || '—'}</code>
          <button type="button" className="btn-ghost text-sm" onClick={copyReferral}>Copy</button>
        </div>
        <p className="text-sm text-slate-400">
          Successful referrals: {referrals.filter((r) => r.status === 'rewarded').length} / {referrals.length}
        </p>
      </section>

      <section className="card p-6 space-y-3">
        <h2 className="font-display font-semibold text-xl text-white">Available coupons</h2>
        {coupons.length === 0 ? (
          <p className="text-sm text-slate-500">No coupons available right now.</p>
        ) : (
          <ul className="space-y-2">
            {coupons.map((c) => (
              <li key={c.id} className="flex justify-between text-sm border-b border-brand-500/10 pb-2">
                <span>
                  <span className="text-brand-400 font-mono">{c.code}</span>
                  <span className="text-slate-400 ml-2">{c.name}</span>
                </span>
                <Link to="/checkout" className="text-xs text-brand-400 hover:underline">Use at checkout</Link>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="card p-6 space-y-3">
        <h2 className="font-display font-semibold text-xl text-white">Gift card balance</h2>
        <form onSubmit={handleGiftLookup} className="flex gap-2">
          <input
            className="input flex-1"
            value={giftLookup}
            onChange={(e) => setGiftLookup(e.target.value.toUpperCase())}
            placeholder="Enter gift card code"
            aria-label="Gift card code"
          />
          <button type="submit" className="btn-secondary">Check</button>
        </form>
        {giftCard && (
          <p className="text-sm text-slate-300">
            {giftCard.code}: {formatCurrency(giftCard.balance)} ({giftCard.status})
          </p>
        )}
      </section>

      <section className="card p-6 space-y-3">
        <h2 className="font-display font-semibold text-xl text-white">Recent rewards</h2>
        {transactions.length === 0 ? (
          <p className="text-sm text-slate-500">No loyalty activity yet. Place an order to earn points.</p>
        ) : (
          <ul className="space-y-2">
            {transactions.map((tx) => (
              <li key={tx.id} className="flex justify-between text-sm text-slate-300">
                <span>{tx.description || tx.txType}</span>
                <span className={tx.points >= 0 ? 'text-brand-400' : 'text-red-400'}>
                  {tx.points >= 0 ? '+' : ''}{tx.points}
                </span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
