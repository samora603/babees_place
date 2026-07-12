import { useEffect, useState } from 'react';
import { productService } from '@/services/productService';
import { adminService } from '@/services/adminService';
import { generateSlug } from '@/utils/slug';
import { validateCategoryForm } from '@/utils/productValidation';
import Button from '@/components/ui/Button';
import Modal from '@/components/ui/Modal';
import Spinner from '@/components/ui/Spinner';
import { FiEdit2, FiPlus, FiTrash2 } from 'react-icons/fi';
import toast from 'react-hot-toast';

const emptyForm = { name: '', slug: '' };

export default function AdminCategories() {
  const [categories, setCategories] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState(emptyForm);
  const [errors, setErrors] = useState({});
  const [saving, setSaving] = useState(false);

  const fetchCategories = () => {
    setLoading(true);
    productService.getCategories()
      .then(({ data }) => setCategories(data.data || []))
      .finally(() => setLoading(false));
  };

  useEffect(fetchCategories, []);

  const openCreate = () => {
    setEditingId(null);
    setForm(emptyForm);
    setErrors({});
    setModalOpen(true);
  };

  const openEdit = (cat) => {
    setEditingId(cat.id);
    setForm({ name: cat.name || '', slug: cat.slug || '' });
    setErrors({});
    setModalOpen(true);
  };

  const closeModal = () => {
    setModalOpen(false);
    setEditingId(null);
    setForm(emptyForm);
    setErrors({});
  };

  const handleNameChange = (e) => {
    const name = e.target.value;
    setForm((prev) => ({
      ...prev,
      name,
      slug: editingId ? prev.slug : generateSlug(name),
    }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    const validation = validateCategoryForm(form);
    if (!validation.valid) {
      setErrors(validation.errors);
      return;
    }
    setSaving(true);
    try {
      const payload = {
        name: form.name.trim(),
        slug: form.slug?.trim() || generateSlug(form.name),
      };
      const result = editingId
        ? await adminService.updateCategory(editingId, payload)
        : await adminService.createCategory(payload);
      if (result.data.error) throw result.data.error;
      toast.success(editingId ? 'Category updated' : 'Category created');
      closeModal();
      fetchCategories();
    } catch (err) {
      toast.error(err.message || 'Save failed');
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setSaving(true);
    try {
      const result = await adminService.deleteCategory(deleteTarget.id);
      if (result.data.error) throw result.data.error;
      toast.success('Category deleted');
      setDeleteTarget(null);
      fetchCategories();
    } catch (err) {
      toast.error(err.message || 'Delete failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-6 p-6">
      <div className="flex items-center justify-between">
        <h1 className="font-display font-bold text-2xl">Categories</h1>
        <Button onClick={openCreate} className="flex items-center gap-2 text-sm">
          <FiPlus /> New Category
        </Button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><Spinner size="lg" /></div>
      ) : categories.length === 0 ? (
        <div className="card p-10 text-center space-y-4">
          <p className="text-slate-400">No categories yet. Create your first category to organize products.</p>
          <Button onClick={openCreate}>Create Category</Button>
        </div>
      ) : (
        <div className="card overflow-hidden">
          <table className="w-full text-sm">
            <thead className="border-b border-surface-border">
              <tr className="text-xs text-slate-400 uppercase tracking-wider">
                <th className="text-left p-4">Name</th>
                <th className="text-left p-4">Slug</th>
                <th className="p-4" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-border">
              {categories.map((cat) => (
                <tr key={cat.id} className="hover:bg-surface/50">
                  <td className="p-4 font-medium">{cat.name}</td>
                  <td className="p-4 text-slate-400 font-mono text-xs">{cat.slug || '—'}</td>
                  <td className="p-4">
                    <div className="flex items-center gap-2 justify-end">
                      <button
                        type="button"
                        onClick={() => openEdit(cat)}
                        className="btn-ghost p-1.5 text-slate-400 hover:text-white"
                        aria-label={`Edit ${cat.name}`}
                      >
                        <FiEdit2 size={16} />
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeleteTarget(cat)}
                        className="btn-ghost p-1.5 text-slate-400 hover:text-red-400"
                        aria-label={`Delete ${cat.name}`}
                      >
                        <FiTrash2 size={16} />
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Modal isOpen={modalOpen} onClose={closeModal} title={editingId ? 'Edit Category' : 'New Category'}>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Name *</label>
            <input required value={form.name} onChange={handleNameChange} className="input w-full" />
            {errors.name && <p className="text-xs text-red-400 mt-1">{errors.name}</p>}
          </div>
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Slug</label>
            <input value={form.slug} onChange={(e) => setForm((p) => ({ ...p, slug: e.target.value }))} className="input w-full font-mono text-sm" />
            {errors.slug && <p className="text-xs text-red-400 mt-1">{errors.slug}</p>}
          </div>
          <div className="flex gap-3 pt-2">
            <Button type="submit" loading={saving}>{editingId ? 'Update' : 'Create'}</Button>
            <Button type="button" variant="secondary" onClick={closeModal}>Cancel</Button>
          </div>
        </form>
      </Modal>

      <Modal isOpen={!!deleteTarget} onClose={() => setDeleteTarget(null)} title="Delete Category" size="sm">
        <p className="text-sm text-slate-300 mb-4">
          Delete <strong>{deleteTarget?.name}</strong>? Products in this category will become uncategorized.
        </p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setDeleteTarget(null)}>Cancel</Button>
          <Button loading={saving} onClick={handleDelete} className="bg-red-600 hover:bg-red-500">Delete</Button>
        </div>
      </Modal>
    </div>
  );
}
