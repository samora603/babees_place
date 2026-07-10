import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { productService } from '@/services/productService';
import { formatCurrency } from '@/utils/helpers';
import Spinner from '@/components/ui/Spinner';
import Pagination from '@/components/ui/Pagination';
import { FiPlus, FiEdit2, FiPower } from 'react-icons/fi';
import toast from 'react-hot-toast';

export default function AdminProducts() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pages, setPages] = useState(1);
  const [search, setSearch] = useState('');

  const fetchProducts = () => {
    setLoading(true);
    productService.getProducts({ page, limit: 20, ...(search && { search }) })
      .then(({ data }) => { setProducts(data.data); setPages(data.pages); })
      .finally(() => setLoading(false));
  };

  useEffect(fetchProducts, [page, search]);

  const handleToggle = async (id, isActive) => {
    try {
      await adminService.updateProduct(id, { isActive: !isActive });
      fetchProducts();
      toast.success(isActive ? 'Product deactivated' : 'Product activated');
    } catch { toast.error('Action failed'); }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display font-bold text-2xl">Products</h1>
        <Link to="/admin/products/new" id="admin-new-product-btn" className="btn-primary flex items-center gap-2 text-sm">
          <FiPlus /> New Product
        </Link>
      </div>

      <input type="search" placeholder="Search products…" value={search} onChange={(e) => setSearch(e.target.value)} className="input max-w-xs" id="admin-product-search" />

      {loading ? <div className="flex justify-center py-16"><Spinner size="lg" /></div> : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="border-b border-surface-border">
              <tr className="text-xs text-slate-400 uppercase tracking-wider">
                <th className="text-left p-4">Product</th>
                <th className="text-left p-4">Price</th>
                <th className="text-left p-4">Stock</th>
                <th className="text-left p-4">Category</th>
                <th className="text-left p-4">Status</th>
                <th className="p-4" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-border">
              {products.map((p) => (
                <tr key={p._id} className="hover:bg-surface/50 transition-colors">
                  <td className="p-4">
                    <div className="flex items-center gap-3">
                      <img src={p.images?.[0]?.url || '/placeholder.png'} alt={p.name} className="w-10 h-10 object-cover rounded-lg" />
                      <span className="font-medium line-clamp-1">{p.name}</span>
                    </div>
                  </td>
                  <td className="p-4 text-brand-400 font-semibold">{formatCurrency(p.discountPrice || p.price)}</td>
                  <td className="p-4">
                    <span className={p.stock <= 5 ? 'text-orange-400' : 'text-slate-300'}>{p.stock}</span>
                  </td>
                  <td className="p-4 text-slate-400">{p.category?.name}</td>
                  <td className="p-4">
                    <span className={`badge ${p.isActive ? 'bg-green-400/10 text-green-400' : 'bg-slate-700 text-slate-400'}`}>
                      {p.isActive ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="p-4">
                    <div className="flex items-center gap-2 justify-end">
                      <Link to={`/admin/products/${p._id}/edit`} className="btn-ghost p-1.5 text-slate-400 hover:text-white"><FiEdit2 size={16} /></Link>
                      <button onClick={() => handleToggle(p._id, p.isActive)} className="btn-ghost p-1.5 text-slate-400 hover:text-brand-400"><FiPower size={16} /></button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} pages={pages} onPage={setPage} />
    </div>
  );
}
