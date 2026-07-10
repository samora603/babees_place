import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { productService } from '@/services/productService';
import { adminService } from '@/services/adminService';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function AdminProductForm() {
  const { id } = useParams();
  const navigate = useNavigate();
  const isEdit = !!id;
  const [categories, setCategories] = useState([]);
  const [images, setImages] = useState([]);
  const [saving, setSaving] = useState(false);
  const [form, setForm] = useState({
    name: '', description: '', price: '', discountPrice: '', stock: '', lowStockThreshold: 5,
    category: '', isFeatured: false, isActive: true, shortDescription: '', weight: '',
  });

  useEffect(() => {
    productService.getCategories().then(({ data }) => setCategories(data.data));
    if (isEdit) {
      productService.getProduct(id).then(({ data }) => {
        const p = data.data;
        setForm({ name: p.name, description: p.description, price: p.price, discountPrice: p.discountPrice || '', stock: p.stock, lowStockThreshold: p.lowStockThreshold, category: p.category?._id, isFeatured: p.isFeatured, isActive: p.isActive, shortDescription: p.shortDescription || '', weight: p.weight || '' });
      });
    }
  }, [id]);

  const set = (field) => (e) => setForm((prev) => ({ ...prev, [field]: e.target.type === 'checkbox' ? e.target.checked : e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      let result;
      // Clean payload for optional numbers
      const payload = { ...form };
      ['discountPrice', 'weight', 'lowStockThreshold'].forEach(key => {
        if (payload[key] === '') {
          delete payload[key];
        } else if (payload[key] !== undefined) {
          payload[key] = Number(payload[key]);
        }
      });
      ['price', 'stock'].forEach(key => {
        payload[key] = Number(payload[key]);
      });

      if (isEdit) {
        result = await adminService.updateProduct(id, payload);
      } else {
        result = await adminService.createProduct(payload);
      }
      const productId = result.data.data._id;

      // Upload images if selected
      if (images.length > 0) {
        const formData = new FormData();
        images.forEach((f) => formData.append('images', f));
        await adminService.uploadImages(productId, formData);
      }

      toast.success(isEdit ? 'Product updated' : 'Product created');
      navigate('/admin/products');
    } catch (err) {
      toast.error(err.response?.data?.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="max-w-2xl space-y-6">
      <h1 className="font-display font-bold text-2xl">{isEdit ? 'Edit Product' : 'New Product'}</h1>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Basic Info</h2>
        <div><label className="text-sm text-slate-400 block mb-1.5">Name *</label><input required value={form.name} onChange={set('name')} className="input" id="pf-name" /></div>
        <div><label className="text-sm text-slate-400 block mb-1.5">Short Description</label><input value={form.shortDescription} onChange={set('shortDescription')} className="input" id="pf-short-desc" /></div>
        <div><label className="text-sm text-slate-400 block mb-1.5">Description *</label><textarea required value={form.description} onChange={set('description')} rows={5} className="input" id="pf-description" /></div>
        <div><label className="text-sm text-slate-400 block mb-1.5">Category *</label>
          <select required value={form.category} onChange={set('category')} className="input" id="pf-category">
            <option value="">Select…</option>
            {categories.map((c) => <option key={c._id} value={c._id}>{c.name}</option>)}
          </select>
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Pricing & Inventory</h2>
        <div className="grid grid-cols-2 gap-4">
          <div><label className="text-sm text-slate-400 block mb-1.5">Price (KES) *</label><input required type="number" min="0" value={form.price} onChange={set('price')} className="input" id="pf-price" /></div>
          <div><label className="text-sm text-slate-400 block mb-1.5">Discount Price</label><input type="number" min="0" value={form.discountPrice} onChange={set('discountPrice')} className="input" id="pf-discount" /></div>
          <div><label className="text-sm text-slate-400 block mb-1.5">Stock *</label><input required type="number" min="0" value={form.stock} onChange={set('stock')} className="input" id="pf-stock" /></div>
          <div><label className="text-sm text-slate-400 block mb-1.5">Low Stock Alert</label><input type="number" min="0" value={form.lowStockThreshold} onChange={set('lowStockThreshold')} className="input" id="pf-low-stock" /></div>
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Images</h2>
        <input type="file" accept="image/*" multiple onChange={(e) => setImages(Array.from(e.target.files))} className="text-sm text-slate-300" id="pf-images" />
        {images.length > 0 && <p className="text-xs text-slate-400">{images.length} image{images.length > 1 ? 's' : ''} selected</p>}
      </div>

      <div className="flex items-center gap-6">
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.isFeatured} onChange={set('isFeatured')} className="accent-brand-500" id="pf-featured" />
          <span className="text-sm text-slate-300">Featured</span>
        </label>
        <label className="flex items-center gap-2 cursor-pointer">
          <input type="checkbox" checked={form.isActive} onChange={set('isActive')} className="accent-brand-500" id="pf-active" />
          <span className="text-sm text-slate-300">Active</span>
        </label>
      </div>

      <div className="flex gap-4">
        <Button type="submit" loading={saving}>{isEdit ? 'Update Product' : 'Create Product'}</Button>
        <Button type="button" variant="secondary" onClick={() => navigate('/admin/products')}>Cancel</Button>
      </div>
    </form>
  );
}
