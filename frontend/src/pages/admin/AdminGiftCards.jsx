import { useEffect, useState } from 'react';
import { giftCardService } from '@/services/giftCardService';
import { formatCurrency } from '@/utils/helpers';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

export default function AdminGiftCards() {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [code, setCode] = useState('');
  const [balance, setBalance] = useState(1000);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      setItems(await giftCardService.listGiftCards());
    } catch (err) {
      toast.error(err.message || 'Failed to load gift cards');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleCreate = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      await giftCardService.createGiftCard({
        code: code || undefined,
        initialBalance: Number(balance),
      });
      toast.success('Gift card created');
      setCode('');
      await load();
    } catch (err) {
      toast.error(err.message || 'Create failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-8 space-y-8">
      <header>
        <h1 className="font-display text-2xl text-white tracking-widest uppercase">Gift Cards</h1>
        <p className="text-slate-400 text-sm mt-1">Issue cards and track balances.</p>
      </header>

      <form onSubmit={handleCreate} className="card p-6 flex flex-wrap gap-3 items-end">
        <div>
          <label className="text-xs text-slate-500 block mb-1">Code (optional)</label>
          <input className="input" value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} />
        </div>
        <div>
          <label className="text-xs text-slate-500 block mb-1">Initial balance</label>
          <input className="input" type="number" min={1} value={balance}
            onChange={(e) => setBalance(e.target.value)} required />
        </div>
        <Button type="submit" loading={saving}>Issue card</Button>
      </form>

      {loading ? <Spinner /> : (
        <table className="w-full text-sm">
          <thead className="text-slate-500 text-xs uppercase">
            <tr>
              <th className="text-left py-2">Code</th>
              <th className="text-left">Balance</th>
              <th className="text-left">Status</th>
              <th />
            </tr>
          </thead>
          <tbody>
            {items.map((g) => (
              <tr key={g.id} className="border-t border-brand-500/10 text-slate-300">
                <td className="py-3 font-mono text-brand-400">{g.code}</td>
                <td>{formatCurrency(g.balance)} / {formatCurrency(g.initialBalance)}</td>
                <td>{g.status}</td>
                <td>
                  {g.status === 'active' && (
                    <button
                      type="button"
                      className="text-xs text-amber-400"
                      onClick={async () => {
                        await giftCardService.updateGiftCardStatus(g.id, 'disabled');
                        load();
                      }}
                    >
                      Disable
                    </button>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
