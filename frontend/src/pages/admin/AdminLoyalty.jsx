import { useEffect, useState } from 'react';
import { loyaltyService } from '@/services/loyaltyService';
import { referralService } from '@/services/referralService';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

export default function AdminLoyalty() {
  const [rule, setRule] = useState(null);
  const [referrals, setReferrals] = useState([]);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    (async () => {
      setLoading(true);
      try {
        const [r, refs] = await Promise.all([
          loyaltyService.getActiveLoyaltyRule(),
          referralService.listAllReferrals().catch(() => []),
        ]);
        setRule(r);
        setReferrals(refs);
      } catch (err) {
        toast.error(err.message || 'Failed to load loyalty settings');
      } finally {
        setLoading(false);
      }
    })();
  }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      const saved = await loyaltyService.upsertLoyaltyRule({
        ...rule,
        code: rule.code || 'default',
        name: rule.name || 'Default loyalty rules',
      });
      setRule(saved);
      toast.success('Loyalty rules saved');
    } catch (err) {
      toast.error(err.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  if (loading || !rule) {
    return <div className="p-8 flex justify-center"><Spinner /></div>;
  }

  return (
    <div className="p-8 space-y-8">
      <header>
        <h1 className="font-display text-2xl text-white tracking-widest uppercase">Loyalty & Referrals</h1>
        <p className="text-slate-400 text-sm mt-1">Earn/redeem rates and referral report.</p>
      </header>

      <form onSubmit={handleSave} className="card p-6 grid md:grid-cols-2 gap-4 max-w-3xl">
        <div>
          <label className="text-xs text-slate-500 block mb-1">Earn points per KES</label>
          <input className="input w-full" type="number" step="0.001"
            value={rule.earnPointsPerCurrency}
            onChange={(e) => setRule((r) => ({ ...r, earnPointsPerCurrency: Number(e.target.value) }))} />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Points per KES redeemed</label>
          <input className="input w-full" type="number"
            value={rule.redeemPointsPerCurrency}
            onChange={(e) => setRule((r) => ({ ...r, redeemPointsPerCurrency: Number(e.target.value) }))} />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Min redeem points</label>
          <input className="input w-full" type="number"
            value={rule.minRedeemPoints}
            onChange={(e) => setRule((r) => ({ ...r, minRedeemPoints: Number(e.target.value) }))} />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Max redeem % of subtotal</label>
          <input className="input w-full" type="number"
            value={rule.maxRedeemPercent}
            onChange={(e) => setRule((r) => ({ ...r, maxRedeemPercent: Number(e.target.value) }))} />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Free delivery points</label>
          <input className="input w-full" type="number"
            value={rule.freeDeliveryPoints}
            onChange={(e) => setRule((r) => ({ ...r, freeDeliveryPoints: Number(e.target.value) }))} />
        </div>
        <Button type="submit" loading={saving}>Save rules</Button>
      </form>

      <section>
        <h2 className="font-display text-lg text-white mb-4">Referral report</h2>
        <table className="w-full text-sm">
          <thead className="text-slate-500 text-xs uppercase">
            <tr>
              <th className="text-left py-2">Code</th>
              <th className="text-left">Status</th>
              <th className="text-left">Referrer pts</th>
              <th className="text-left">Referred pts</th>
            </tr>
          </thead>
          <tbody>
            {referrals.map((r) => (
              <tr key={r.id} className="border-t border-brand-500/10 text-slate-300">
                <td className="py-3 font-mono">{r.referralCode}</td>
                <td>{r.status}</td>
                <td>{r.rewardPoints}</td>
                <td>{r.referredRewardPoints}</td>
              </tr>
            ))}
            {referrals.length === 0 && (
              <tr><td colSpan={4} className="py-4 text-slate-500">No referrals yet.</td></tr>
            )}
          </tbody>
        </table>
      </section>
    </div>
  );
}
