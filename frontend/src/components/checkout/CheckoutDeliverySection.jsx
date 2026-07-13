import { ADDRESS_LABELS } from '@/models/address';
import AddressForm from '@/components/profile/AddressForm';

const emptyCheckoutAddress = { line1: '', line2: '', city: '', phone: '', notes: '' };

/**
 * Delivery address UI for checkout — saved, new (optional save), or one-time entry.
 */
export default function CheckoutDeliverySection({
  savedAddresses,
  addressMode,
  onAddressModeChange,
  selectedAddressId,
  onSelectSavedAddress,
  deliveryAddress,
  onDeliveryAddressChange,
  newAddressForm,
  onNewAddressFieldChange,
  saveNewAddress,
  onSaveNewAddressChange,
  newAddressErrors = {},
  errors = {},
}) {
  return (
    <div className="space-y-4">
      {savedAddresses.length > 0 && (
        <fieldset className="space-y-2">
          <legend className="text-sm text-slate-400 mb-2">Delivery address</legend>
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
              <input
                type="radio"
                name="addressMode"
                checked={addressMode === 'saved'}
                onChange={() => onAddressModeChange('saved')}
              />
              Use a saved address
            </label>
            {addressMode === 'saved' && (
              <select
                className="input w-full ml-6"
                value={selectedAddressId}
                onChange={(e) => onSelectSavedAddress(e.target.value)}
                aria-label="Select saved address"
              >
                <option value="">Choose address…</option>
                {savedAddresses.map((address) => (
                  <option key={address.id} value={address.id}>
                    {ADDRESS_LABELS[address.label]} — {address.streetAddress}, {address.town}
                    {address.isDefault ? ' (Default)' : ''}
                  </option>
                ))}
              </select>
            )}

            <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
              <input
                type="radio"
                name="addressMode"
                checked={addressMode === 'new'}
                onChange={() => onAddressModeChange('new')}
              />
              Add a new address
            </label>

            <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
              <input
                type="radio"
                name="addressMode"
                checked={addressMode === 'once'}
                onChange={() => onAddressModeChange('once')}
              />
              Enter a one-time address (not saved)
            </label>
          </div>
        </fieldset>
      )}

      {addressMode === 'saved' && savedAddresses.length > 0 && selectedAddressId && (
        <p className="text-xs text-slate-500 ml-6">
          Using saved address. Order will ship to the selected location.
        </p>
      )}

      {addressMode === 'new' && (
        <div className="rounded-xl border border-brand-500/10 p-4 space-y-4 bg-[#0B0B0B]/40">
          <AddressForm
            form={newAddressForm}
            errors={newAddressErrors}
            onChange={onNewAddressFieldChange}
            idPrefix="checkout-new-address"
          />
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={saveNewAddress}
              onChange={(e) => onSaveNewAddressChange(e.target.checked)}
            />
            Save this address to my account
          </label>
        </div>
      )}

      {(addressMode === 'once' || savedAddresses.length === 0) && addressMode !== 'new' && (
        <div className="space-y-3">
          {savedAddresses.length === 0 && (
            <p className="text-xs text-slate-500">No saved addresses yet. Enter delivery details below.</p>
          )}
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Address line 1 *</label>
            <input
              className="input w-full"
              value={deliveryAddress.line1}
              onChange={(e) => onDeliveryAddressChange('line1', e.target.value)}
            />
            {errors.line1 && <p className="text-xs text-red-400">{errors.line1}</p>}
          </div>
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Address line 2 / County</label>
            <input
              className="input w-full"
              value={deliveryAddress.line2}
              onChange={(e) => onDeliveryAddressChange('line2', e.target.value)}
            />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-sm text-slate-400 block mb-1.5">City *</label>
              <input
                className="input w-full"
                value={deliveryAddress.city}
                onChange={(e) => onDeliveryAddressChange('city', e.target.value)}
              />
              {errors.city && <p className="text-xs text-red-400">{errors.city}</p>}
            </div>
            <div>
              <label className="text-sm text-slate-400 block mb-1.5">Phone *</label>
              <input
                className="input w-full"
                placeholder="+254..."
                value={deliveryAddress.phone}
                onChange={(e) => onDeliveryAddressChange('phone', e.target.value)}
              />
              {errors.phone && <p className="text-xs text-red-400">{errors.phone}</p>}
            </div>
          </div>
          <div>
            <label className="text-sm text-slate-400 block mb-1.5">Delivery notes</label>
            <input
              className="input w-full"
              value={deliveryAddress.notes}
              onChange={(e) => onDeliveryAddressChange('notes', e.target.value)}
            />
          </div>
        </div>
      )}
    </div>
  );
}

export { emptyCheckoutAddress };
