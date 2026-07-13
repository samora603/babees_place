import { useEffect, useState } from 'react';
import { promotionService } from '@/services/promotionService';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

const EMPTY = {
  name: '',
  code: '',
  promoType: 'percentage',
  status: 'active',
  priority: 100,
  stackable: false,
  percentOff: 10,
  amountOff: '',
  minOrderAmount: 0,
};

export default function AdminPromotions() {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      setItems(await promotionService.listAllPromotions());
    } catch (err) {
      toast.error(err.message || 'Failed to load promotions');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      await promotionService.upsertPromotion({
        ...form,
        percentOff: form.percentOff === '' ? null : Number(form.percentOff),
        amountOff: form.amountOff === '' ? null : Number(form.amountOff),
        minOrderAmount: Number(form.minOrderAmount) || 0,
        priority: Number(form.priority) || 100,
      });
      toast.success('Promotion saved');
      setForm(EMPTY);
      await load();
    } catch (err) {
      toast.error(err.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="p-8 space-y-8">
      <header>
        <h1 className="font-display text-2xl text-white tracking-widest uppercase">Promotions</h1>
        <p className="text-slate-400 text-sm mt-1">Storewide, category, BXGY, and delivery campaigns.</p>
      </header>

      <form onSubmit={handleSave} className="card p-6 grid md:grid-cols-2 gap-4">
        <input className="input" placeholder="Name" required value={form.name}
          onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        <input className="input" placeholder="Code (optional)" value={form.code}
          onChange={(e) => setForm((f) => ({ ...f, code: e.target.value.toUpperCase() }))} />
        <select className="input" value={form.promoType}
          onChange={(e) => setForm((f) => ({ ...f, promoType: e.target.value }))}>
          {['percentage', 'fixed', 'free_delivery', 'buy_x_get_y', 'category', 'product', 'storewide'].map((t) => (
            <option key={t} value={t}>{t}</option>
          ))}
        </select>
        <select className="input" value={form.status}
          onChange={(e) => setForm((f) => ({ ...f, status: e.target.value }))}>
          {['draft', 'active', 'paused', 'expired'].map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
        <input className="input" type="number" placeholder="% off" value={form.percentOff}
          onChange={(e) => setForm((f) => ({ ...f, percentOff: e.target.value }))} />
        <input className="input" type="number" placeholder="Amount off" value={form.amountOff}
          onChange={(e) => setForm((f) => ({ ...f, amountOff: e.target.value }))} />
        <input className="input" type="number" placeholder="Min order" value={form.minOrderAmount}
          onChange={(e) => setForm((f) => ({ ...f, minOrderAmount: e.target.value }))} />
        <input className="input" type="number" placeholder="Priority" value={form.priority}
          onChange={(e) => setForm((f) => ({ ...f, priority: e.target.value }))} />
        <label className="flex items-center gap-2 text-sm text-slate-300">
          <input type="checkbox" checked={form.stackable}
            onChange={(e) => setForm((f) => ({ ...f, stackable: e.target.checked }))} />
          Stackable
        </label>
        <Button type="submit" loading={saving}>Save promotion</Button>
      </form>

      {loading ? <Spinner /> : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm text-left">
            <thead className="text-slate-500 uppercase text-xs">
              <tr>
                <th className="py-2">Name</th>
                <th>Type</th>
                <th>Status</th>
                <th>Priority</th>
                <th />
              </tr>
            </thead>
            <tbody>
              {items.map((p) => (
                <tr key={p.id} className="border-t border-brand-500/10 text-slate-300">
                  <td className="py-3">{p.name}</td>
                  <td>{p.promoType}</td>
                  <td>{p.status}</td>
                  <td>{p.priority}</td>
                  <td>
                    <button
                      type="button"
                      className="text-xs text-red-400"
                      onClick={async () => {
                        await promotionService.deletePromotion(p.id);
                        load();
                      }}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
