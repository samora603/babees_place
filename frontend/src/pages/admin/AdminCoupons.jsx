import { useEffect, useState } from 'react';
import { couponService } from '@/services/couponService';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

const EMPTY = {
  code: '',
  name: '',
  discountType: 'percentage',
  percentOff: 10,
  amountOff: '',
  minOrderAmount: 0,
  usageLimit: '',
  perUserLimit: 1,
  isOneTime: false,
  isActive: true,
};

export default function AdminCoupons() {
  const [items, setItems] = useState([]);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      setItems(await couponService.listCoupons());
    } catch (err) {
      toast.error(err.message || 'Failed to load coupons');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      await couponService.upsertCoupon({
        ...form,
        percentOff: form.percentOff === '' ? null : Number(form.percentOff),
        amountOff: form.amountOff === '' ? null : Number(form.amountOff),
        usageLimit: form.usageLimit === '' ? null : Number(form.usageLimit),
        minOrderAmount: Number(form.minOrderAmount) || 0,
        perUserLimit: Number(form.perUserLimit) || 1,
      });
      toast.success('Coupon saved');
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
        <h1 className="font-display text-2xl text-white tracking-widest uppercase">Coupons</h1>
        <p className="text-slate-400 text-sm mt-1">Codes, limits, and validity windows.</p>
      </header>

      <form onSubmit={handleSave} className="card p-6 grid md:grid-cols-2 gap-4">
        <input className="input" placeholder="CODE" required value={form.code}
          onChange={(e) => setForm((f) => ({ ...f, code: e.target.value.toUpperCase() }))} />
        <input className="input" placeholder="Name" required value={form.name}
          onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))} />
        <select className="input" value={form.discountType}
          onChange={(e) => setForm((f) => ({ ...f, discountType: e.target.value }))}>
          <option value="percentage">percentage</option>
          <option value="fixed">fixed</option>
          <option value="free_delivery">free_delivery</option>
        </select>
        <input className="input" type="number" placeholder="% off" value={form.percentOff}
          onChange={(e) => setForm((f) => ({ ...f, percentOff: e.target.value }))} />
        <input className="input" type="number" placeholder="Amount off" value={form.amountOff}
          onChange={(e) => setForm((f) => ({ ...f, amountOff: e.target.value }))} />
        <input className="input" type="number" placeholder="Min order" value={form.minOrderAmount}
          onChange={(e) => setForm((f) => ({ ...f, minOrderAmount: e.target.value }))} />
        <input className="input" type="number" placeholder="Global usage limit" value={form.usageLimit}
          onChange={(e) => setForm((f) => ({ ...f, usageLimit: e.target.value }))} />
        <input className="input" type="number" placeholder="Per-user limit" value={form.perUserLimit}
          onChange={(e) => setForm((f) => ({ ...f, perUserLimit: e.target.value }))} />
        <label className="flex items-center gap-2 text-sm text-slate-300">
          <input type="checkbox" checked={form.isOneTime}
            onChange={(e) => setForm((f) => ({ ...f, isOneTime: e.target.checked }))} />
          One-time
        </label>
        <Button type="submit" loading={saving}>Save coupon</Button>
      </form>

      {loading ? <Spinner /> : (
        <table className="w-full text-sm">
          <thead className="text-slate-500 text-xs uppercase">
            <tr>
              <th className="text-left py-2">Code</th>
              <th className="text-left">Type</th>
              <th className="text-left">Uses</th>
              <th className="text-left">Active</th>
            </tr>
          </thead>
          <tbody>
            {items.map((c) => (
              <tr key={c.id} className="border-t border-brand-500/10 text-slate-300">
                <td className="py-3 font-mono text-brand-400">{c.code}</td>
                <td>{c.discountType}</td>
                <td>{c.usageCount}{c.usageLimit != null ? ` / ${c.usageLimit}` : ''}</td>
                <td>{c.isActive ? 'yes' : 'no'}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}
