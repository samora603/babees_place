import { useCallback, useEffect, useState } from 'react';
import { FiEdit2, FiPlus, FiStar, FiTrash2 } from 'react-icons/fi';
import { addressService } from '@/services/addressService';
import { ADDRESS_LABELS, EMPTY_ADDRESS_FORM } from '@/models/address';
import AddressForm from './AddressForm';
import ProfileSection from './ProfileSection';
import Button from '@/components/ui/Button';
import Modal from '@/components/ui/Modal';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

function addressToForm(address) {
  if (!address) return { ...EMPTY_ADDRESS_FORM };
  return {
    label: address.label,
    recipientName: address.recipientName,
    phone: address.phone,
    county: address.county,
    town: address.town,
    streetAddress: address.streetAddress,
    additionalDirections: address.additionalDirections,
    isDefault: address.isDefault,
  };
}

export default function AddressBook() {
  const [addresses, setAddresses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [modalOpen, setModalOpen] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [editingId, setEditingId] = useState(null);
  const [form, setForm] = useState({ ...EMPTY_ADDRESS_FORM });
  const [formErrors, setFormErrors] = useState({});
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    const { data, error: fetchError } = await addressService.getAddresses();
    setAddresses(data);
    setError(fetchError || null);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  const openCreate = () => {
    setEditingId(null);
    setForm({ ...EMPTY_ADDRESS_FORM, isDefault: addresses.length === 0 });
    setFormErrors({});
    setModalOpen(true);
  };

  const openEdit = (address) => {
    setEditingId(address.id);
    setForm(addressToForm(address));
    setFormErrors({});
    setModalOpen(true);
  };

  const handleFieldChange = (field, value) => {
    setForm((prev) => ({ ...prev, [field]: value }));
  };

  const handleSave = async () => {
    setSaving(true);
    setFormErrors({});
    const action = editingId
      ? addressService.updateAddress(editingId, form)
      : addressService.createAddress(form);
    const { data, error: saveError } = await action;
    setSaving(false);

    if (saveError) {
      if (saveError.details) setFormErrors(saveError.details);
      toast.error(saveError.message || 'Could not save address');
      return;
    }

    if (form.isDefault && data?.id) {
      await addressService.setDefaultAddress(data.id);
    }

    toast.success(editingId ? 'Address updated' : 'Address saved');
    setModalOpen(false);
    load();
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    setSaving(true);
    const { error: deleteError } = await addressService.deleteAddress(deleteTarget.id);
    setSaving(false);
    if (deleteError) {
      toast.error(deleteError.message || 'Could not delete address');
      return;
    }
    toast.success('Address deleted');
    setDeleteTarget(null);
    load();
  };

  const handleSetDefault = async (id) => {
    const { error: defaultError } = await addressService.setDefaultAddress(id);
    if (defaultError) {
      toast.error(defaultError.message || 'Could not set default');
      return;
    }
    toast.success('Default address updated');
    load();
  };

  return (
    <ProfileSection
      id="address-book"
      title="Address Book"
      description="Save delivery addresses for faster checkout."
    >
      {loading && (
        <div className="flex justify-center py-8">
          <Spinner />
        </div>
      )}

      {!loading && error && (
        <div className="text-center py-6 space-y-3">
          <p className="text-sm text-red-400">Unable to load addresses.</p>
          <Button variant="secondary" onClick={load}>Retry</Button>
        </div>
      )}

      {!loading && !error && addresses.length === 0 && (
        <p className="text-sm text-slate-400 text-center py-4">No saved addresses yet.</p>
      )}

      {!loading && !error && addresses.length > 0 && (
        <ul className="space-y-3">
          {addresses.map((address) => (
            <li
              key={address.id}
              className="rounded-xl border border-brand-500/10 bg-[#0B0B0B]/50 p-4 flex flex-col sm:flex-row sm:items-start gap-4"
            >
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="text-xs uppercase tracking-widest text-brand-400 font-semibold">
                    {ADDRESS_LABELS[address.label] || address.label}
                  </span>
                  {address.isDefault && (
                    <span className="text-[10px] uppercase tracking-wider text-slate-400 bg-brand-500/10 px-2 py-0.5 rounded">
                      Default
                    </span>
                  )}
                </div>
                <p className="font-medium text-white mt-1">{address.recipientName}</p>
                <p className="text-sm text-slate-400 mt-1">
                  {address.streetAddress}, {address.town}, {address.county}
                </p>
                <p className="text-sm text-slate-500">{address.phone}</p>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                {!address.isDefault && (
                  <button
                    type="button"
                    onClick={() => handleSetDefault(address.id)}
                    className="btn-ghost p-2 text-slate-400 hover:text-brand-400"
                    aria-label={`Set ${address.recipientName} as default`}
                  >
                    <FiStar size={16} />
                  </button>
                )}
                <button
                  type="button"
                  onClick={() => openEdit(address)}
                  className="btn-ghost p-2 text-slate-400 hover:text-white"
                  aria-label={`Edit ${address.recipientName}`}
                >
                  <FiEdit2 size={16} />
                </button>
                <button
                  type="button"
                  onClick={() => setDeleteTarget(address)}
                  className="btn-ghost p-2 text-slate-400 hover:text-red-400"
                  aria-label={`Delete ${address.recipientName}`}
                >
                  <FiTrash2 size={16} />
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <Button type="button" variant="secondary" onClick={openCreate} className="inline-flex items-center gap-2">
        <FiPlus size={16} /> Add Address
      </Button>

      <Modal
        isOpen={modalOpen}
        onClose={() => setModalOpen(false)}
        title={editingId ? 'Edit Address' : 'Add Address'}
        size="lg"
      >
        <AddressForm form={form} errors={formErrors} onChange={handleFieldChange} />
        <div className="flex gap-3 mt-6">
          <Button variant="secondary" type="button" onClick={() => setModalOpen(false)}>Cancel</Button>
          <Button type="button" loading={saving} onClick={handleSave}>Save Address</Button>
        </div>
      </Modal>

      <Modal
        isOpen={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        title="Delete Address"
        size="sm"
      >
        <p className="text-sm text-slate-300 mb-4">
          Delete the address for <strong>{deleteTarget?.recipientName}</strong>? This cannot be undone.
        </p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setDeleteTarget(null)}>Cancel</Button>
          <Button loading={saving} onClick={handleDelete} className="bg-red-600 hover:bg-red-500">Delete</Button>
        </div>
      </Modal>
    </ProfileSection>
  );
}
