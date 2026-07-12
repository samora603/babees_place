import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { productService } from '@/services/productService';
import { formatCurrency, getPrimaryImage } from '@/utils/helpers';
import Spinner from '@/components/ui/Spinner';
import Pagination from '@/components/ui/Pagination';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import { FiPlus, FiEdit2, FiPower, FiTrash2, FiExternalLink, FiStar } from 'react-icons/fi';
import toast from 'react-hot-toast';
import { isLowStock } from '@/constants/inventory';

export default function AdminProducts() {
  const [products, setProducts] = useState([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pages, setPages] = useState(1);
  const [search, setSearch] = useState('');
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);

  const fetchProducts = () => {
    setLoading(true);
    productService.getProducts({ page, limit: 20, includeInactive: true, ...(search && { search }) })
      .then(({ data }) => { setProducts(data.data); setPages(data.pages); })
      .finally(() => setLoading(false));
  };

  useEffect(fetchProducts, [page, search]);

  const handleToggle = async (id, isActive) => {
    try {
      await adminService.updateProduct(id, { is_active: !isActive });
      fetchProducts();
      toast.success(isActive ? 'Product deactivated' : 'Product activated');
    } catch { toast.error('Action failed'); }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      const result = await adminService.deleteProduct(deleteTarget.id);
      if (result.data.error) throw result.data.error;
      toast.success('Product deleted');
      setDeleteTarget(null);
      fetchProducts();
    } catch (err) {
      toast.error(err.message || 'Delete failed');
    } finally {
      setDeleting(false);
    }
  };

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display font-bold text-2xl">Products</h1>
        <Link to="/admin/products/new" id="admin-new-product-btn" className="btn-primary flex items-center gap-2 text-sm">
          <FiPlus /> New Product
        </Link>
      </div>

      <input type="search" placeholder="Search products…" value={search} onChange={(e) => setSearch(e.target.value)} className="input max-w-xs" id="admin-product-search" />

      {loading ? <div className="flex justify-center py-16"><Spinner size="lg" /></div> : products.length === 0 ? (
        <div className="card p-10 text-center space-y-4">
          <p className="text-slate-400">No products found.</p>
          <Link to="/admin/products/new" className="btn-primary inline-flex items-center gap-2 text-sm">
            <FiPlus /> Create Product
          </Link>
        </div>
      ) : (
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
                <tr key={p.id} className="hover:bg-surface/50 transition-colors">
                  <td className="p-4">
                    <div className="flex items-center gap-3">
                      <img src={getPrimaryImage(p.images) || p.image_url || '/placeholder.png'} alt={p.name} className="w-10 h-10 object-cover rounded-lg" />
                      <div>
                        <span className="font-medium line-clamp-1 block">{p.name}</span>
                        {p.featured && (
                          <span className="inline-flex items-center gap-1 text-[10px] text-brand-400 mt-0.5">
                            <FiStar size={10} /> Featured
                          </span>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="p-4 text-brand-400 font-semibold">{formatCurrency(p.discount_price || p.price)}</td>
                  <td className="p-4">
                    <span className={isLowStock(p.stock) ? 'text-orange-400' : 'text-slate-300'}>{p.stock}</span>
                  </td>
                  <td className="p-4 text-slate-400">{p.categories?.name || p.category || '—'}</td>
                  <td className="p-4">
                    <span className={`badge ${p.is_active ? 'bg-green-400/10 text-green-400' : 'bg-slate-700 text-slate-400'}`}>
                      {p.is_active ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="p-4">
                    <div className="flex items-center gap-2 justify-end">
                      {p.slug && (
                        <Link to={`/shop/${p.slug}`} target="_blank" rel="noopener noreferrer" className="btn-ghost p-1.5 text-slate-400 hover:text-brand-400" title="Preview">
                          <FiExternalLink size={16} />
                        </Link>
                      )}
                      <Link to={`/admin/products/${p.id}/edit`} className="btn-ghost p-1.5 text-slate-400 hover:text-white"><FiEdit2 size={16} /></Link>
                      <button onClick={() => handleToggle(p.id, p.is_active)} className="btn-ghost p-1.5 text-slate-400 hover:text-brand-400"><FiPower size={16} /></button>
                      <button onClick={() => setDeleteTarget(p)} className="btn-ghost p-1.5 text-slate-400 hover:text-red-400"><FiTrash2 size={16} /></button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Pagination page={page} pages={pages} onPage={setPage} />

      <Modal isOpen={!!deleteTarget} onClose={() => setDeleteTarget(null)} title="Delete Product" size="sm">
        <p className="text-sm text-slate-300 mb-4">
          Permanently delete <strong>{deleteTarget?.name}</strong>? This removes the product and its storage images. This cannot be undone.
        </p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setDeleteTarget(null)}>Cancel</Button>
          <Button loading={deleting} onClick={handleDelete} className="bg-red-600 hover:bg-red-500">Delete</Button>
        </div>
      </Modal>
    </div>
  );
}
