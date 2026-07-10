import { useEffect, useState } from 'react';
import { adminService } from '@/services/adminService';
import { formatCurrency } from '@/utils/helpers';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

export default function AdminInventory() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');
  const [editing, setEditing] = useState(null); // { id, stock }

  const fetchInventory = () => {
    setLoading(true);
    adminService.getInventory({ limit: 100, stockStatus: filter === 'all' ? undefined : filter })
      .then(({ data }) => setProducts(data.data))
      .finally(() => setLoading(false));
  };

  useEffect(fetchInventory, [filter]);

  const saveStock = async (id) => {
    try {
      await adminService.updateStock(id, { stock: editing.stock });
      toast.success('Stock updated');
      setEditing(null);
      fetchInventory();
    } catch { toast.error('Update failed'); }
  };

  return (
    <div className="space-y-6">
      <h1 className="font-display font-bold text-2xl">Inventory</h1>
      <div className="flex gap-2">
        {['all', 'low', 'out', 'in'].map((f) => (
          <button key={f} onClick={() => setFilter(f)}
            className={`px-4 py-1.5 rounded-full text-sm capitalize transition-all ${filter === f ? 'bg-brand-500 text-white' : 'btn-secondary'}`}>
            {f === 'all' ? 'All' : f === 'low' ? '⚠️ Low Stock' : f === 'out' ? '❌ Out of Stock' : '✅ In Stock'}
          </button>
        ))}
      </div>

      {loading ? <div className="flex justify-center py-16"><Spinner size="lg" /></div> : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="border-b border-surface-border">
              <tr className="text-xs text-slate-400 uppercase tracking-wider">
                <th className="text-left p-4">Product</th>
                <th className="text-left p-4">Category</th>
                <th className="text-left p-4">Price</th>
                <th className="text-left p-4">Stock</th>
                <th className="text-left p-4">Sold</th>
                <th className="p-4" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-border">
              {products.map((p) => (
                <tr key={p._id} className="hover:bg-surface/50 transition-colors">
                  <td className="p-4">
                    <div className="flex items-center gap-3">
                      <img src={p.images?.[0]?.url || '/placeholder.png'} alt={p.name} className="w-8 h-8 rounded-lg object-cover" />
                      <span className="font-medium line-clamp-1">{p.name}</span>
                    </div>
                  </td>
                  <td className="p-4 text-slate-400">{p.category?.name}</td>
                  <td className="p-4 text-brand-400">{formatCurrency(p.price)}</td>
                  <td className="p-4">
                    {editing?.id === p._id ? (
                      <div className="flex gap-2 items-center">
                        <input type="number" min="0" value={editing.stock} onChange={(e) => setEditing({ id: p._id, stock: Number(e.target.value) })} className="input py-1 w-20 text-center" />
                        <button onClick={() => saveStock(p._id)} className="btn-primary text-xs py-1 px-2">Save</button>
                        <button onClick={() => setEditing(null)} className="text-xs text-slate-400 hover:text-white">✕</button>
                      </div>
                    ) : (
                      <span className={p.stock <= p.lowStockThreshold ? 'text-orange-400 font-bold' : 'text-slate-300'}>{p.stock}</span>
                    )}
                  </td>
                  <td className="p-4 text-slate-400">{p.soldCount}</td>
                  <td className="p-4 text-right">
                    <button onClick={() => setEditing({ id: p._id, stock: p.stock })} className="btn-ghost text-xs px-2 py-1 text-brand-400">Edit</button>
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
