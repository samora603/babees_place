import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { productService } from '@/services/productService';
import { adminService } from '@/services/adminService';
import { generateSlug } from '@/utils/slug';
import { validateProductForm } from '@/utils/productValidation';
import {
  mergeUploadedImages,
  normalizeGalleryImages,
  removeImageAt,
  setPrimaryAt,
  validateImageFiles,
} from '@/utils/images';
import ImageGallery from '@/components/admin/ImageGallery';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function AdminProductForm() {
  const { id } = useParams();
  const navigate = useNavigate();
  const isEdit = !!id;
  const [categories, setCategories] = useState([]);
  const [galleryImages, setGalleryImages] = useState([]);
  const [pendingFiles, setPendingFiles] = useState([]);
  const [activeImageIndex, setActiveImageIndex] = useState(0);
  const [removedPaths, setRemovedPaths] = useState([]);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(isEdit);
  const [errors, setErrors] = useState({});
  const [productSlug, setProductSlug] = useState('');
  const [form, setForm] = useState({
    name: '', description: '', price: '', discountPrice: '', stock: '',
    category: '', slug: '', isFeatured: false, isActive: true,
  });

  useEffect(() => {
    productService.getCategories().then(({ data }) => setCategories(data.data));
    if (isEdit) {
      setLoading(true);
      productService.getProductById(id).then(({ data }) => {
        const p = data.data;
        if (!p) {
          toast.error('Product not found');
          navigate('/admin/products');
          return;
        }
        setForm({
          name: p.name || '',
          description: p.description || '',
          price: p.price ?? '',
          discountPrice: p.discount_price ?? '',
          stock: p.stock ?? '',
          category: p.category_id || '',
          slug: p.slug || '',
          isFeatured: !!p.featured,
          isActive: p.is_active ?? true,
        });
        setProductSlug(p.slug || '');
        setGalleryImages(normalizeGalleryImages(p.images || []));
        setLoading(false);
      });
    }
  }, [id, isEdit, navigate]);

  const set = (field) => (e) => {
    const value = e.target.type === 'checkbox' ? e.target.checked : e.target.value;
    setForm((prev) => {
      const next = { ...prev, [field]: value };
      if (field === 'name' && !isEdit && !prev.slugManuallyEdited) {
        next.slug = generateSlug(value);
      }
      return next;
    });
  };

  const handleSlugChange = (e) => {
    setForm((prev) => ({ ...prev, slug: e.target.value, slugManuallyEdited: true }));
  };

  const handleFileChange = (e) => {
    const files = Array.from(e.target.files || []);
    const validation = validateImageFiles(files);
    if (!validation.valid) {
      toast.error(validation.error);
      e.target.value = '';
      return;
    }
    setPendingFiles(files);
  };

  const handleRemoveImage = (index) => {
    const img = galleryImages[index];
    if (img?.path) setRemovedPaths((prev) => [...prev, img.path]);
    setGalleryImages((prev) => removeImageAt(prev, index));
    setActiveImageIndex(0);
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const validation = validateProductForm(form);
    if (!validation.valid) {
      setErrors(validation.errors);
      toast.error('Please fix form errors');
      return;
    }
    setErrors({});
    setSaving(true);
    try {
      const payload = {
        name: form.name.trim(),
        description: form.description.trim(),
        price: Number(form.price),
        stock: Number(form.stock),
        featured: form.isFeatured,
        is_active: form.isActive,
        slug: form.slug?.trim() || generateSlug(form.name),
      };
      if (form.discountPrice !== '' && form.discountPrice != null) {
        payload.discount_price = Number(form.discountPrice);
      } else {
        payload.discount_price = null;
      }
      if (form.category) payload.category_id = form.category;
      else payload.category_id = null;

      const result = isEdit
        ? await adminService.updateProduct(id, payload)
        : await adminService.createProduct(payload);

      if (result.data.error) throw result.data.error;
      const productId = result.data.data?.id;
      if (!productId) throw new Error('Product save failed');

      if (removedPaths.length > 0) {
        const { error: removeErr } = await adminService.deleteStoragePaths(removedPaths);
        if (removeErr) toast.error(`Storage cleanup warning: ${removeErr.message}`);
      }

      let nextImages = normalizeGalleryImages(galleryImages);

      if (pendingFiles.length > 0) {
        const formData = new FormData();
        pendingFiles.forEach((f) => formData.append('images', f));
        const uploadRes = await adminService.uploadImages(productId, formData);
        if (uploadRes.data.error) {
          throw new Error(uploadRes.data.error.message || 'Image upload failed');
        }
        const uploaded = uploadRes.data.data;
        if (!Array.isArray(uploaded) || uploaded.length === 0) {
          throw new Error('Image upload returned no files');
        }
        nextImages = mergeUploadedImages(nextImages, uploaded);
      }

      if (isEdit || pendingFiles.length > 0) {
        const { error: imgErr } = await adminService.updateProduct(productId, { images: nextImages });
        if (imgErr) throw imgErr;
      }

      toast.success(isEdit ? 'Product updated' : 'Product created');
      navigate('/admin/products');
    } catch (err) {
      toast.error(err.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  if (loading) {
    return <div className="p-6 text-slate-400">Loading product…</div>;
  }

  const previewSlug = form.slug || productSlug;

  return (
    <form onSubmit={handleSubmit} className="max-w-2xl space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display font-bold text-2xl">{isEdit ? 'Edit Product' : 'New Product'}</h1>
        {isEdit && previewSlug && (
          <Link to={`/shop/${previewSlug}`} target="_blank" rel="noopener noreferrer" className="text-sm text-brand-400 hover:underline">
            Preview on storefront →
          </Link>
        )}
      </div>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Basic Info</h2>
        <div>
          <label className="text-sm text-slate-400 block mb-1.5">Name *</label>
          <input required value={form.name} onChange={set('name')} className="input" id="pf-name" />
          {errors.name && <p className="text-xs text-red-400 mt-1">{errors.name}</p>}
        </div>
        <div>
          <label className="text-sm text-slate-400 block mb-1.5">Slug</label>
          <input value={form.slug} onChange={handleSlugChange} className="input font-mono text-sm" id="pf-slug" placeholder="auto-generated-from-name" />
          {errors.slug && <p className="text-xs text-red-400 mt-1">{errors.slug}</p>}
          {form.slug && <p className="text-xs text-slate-500 mt-1">URL: /shop/{form.slug}</p>}
        </div>
        <div>
          <label className="text-sm text-slate-400 block mb-1.5">Description *</label>
          <textarea required value={form.description} onChange={set('description')} rows={5} className="input" id="pf-description" />
          {errors.description && <p className="text-xs text-red-400 mt-1">{errors.description}</p>}
        </div>
        <div>
          <label className="text-sm text-slate-400 block mb-1.5">Category</label>
          <select value={form.category} onChange={set('category')} className="input" id="pf-category">
            <option value="">Select…</option>
            {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          {categories.length === 0 && (
            <p className="text-xs text-amber-400 mt-1">
              No categories yet. <Link to="/admin/categories" className="underline">Create categories</Link> first.
            </p>
          )}
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Pricing & Inventory</h2>
        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Price (KES) *</label>
            <input required type="number" min="0" step="0.01" value={form.price} onChange={set('price')} className="input" id="pf-price" />
            {errors.price && <p className="text-xs text-red-400 mt-1">{errors.price}</p>}
          </div>
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Discount Price</label>
            <input type="number" min="0" step="0.01" value={form.discountPrice} onChange={set('discountPrice')} className="input" id="pf-discount" />
            {errors.discountPrice && <p className="text-xs text-red-400 mt-1">{errors.discountPrice}</p>}
          </div>
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Stock *</label>
            <input required type="number" min="0" value={form.stock} onChange={set('stock')} className="input" id="pf-stock" />
            {errors.stock && <p className="text-xs text-red-400 mt-1">{errors.stock}</p>}
          </div>
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h2 className="font-semibold">Images</h2>
        <ImageGallery
          images={galleryImages}
          activeIndex={activeImageIndex}
          onSelect={setActiveImageIndex}
          onSetPrimary={(i) => setGalleryImages((prev) => setPrimaryAt(prev, i))}
          onRemove={handleRemoveImage}
        />
        <input
          type="file"
          accept="image/jpeg,image/png,image/webp"
          multiple
          onChange={handleFileChange}
          className="text-sm text-slate-300"
          id="pf-images"
        />
        {pendingFiles.length > 0 && (
          <p className="text-xs text-slate-400">{pendingFiles.length} new image{pendingFiles.length > 1 ? 's' : ''} will upload on save</p>
        )}
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
