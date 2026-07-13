import { ADDRESS_LABELS, EMPTY_ADDRESS_FORM } from '@/models/address';

/**
 * @param {{
 *   form: typeof EMPTY_ADDRESS_FORM,
 *   errors?: Record<string, string>,
 *   onChange: (field: string, value: string | boolean) => void,
 *   showDefaultToggle?: boolean,
 *   idPrefix?: string,
 * }} props
 */
export default function AddressForm({
  form,
  errors = {},
  onChange,
  showDefaultToggle = true,
  idPrefix = 'address',
}) {
  return (
    <div className="space-y-4">
      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-label`}>Label</label>
        <select
          id={`${idPrefix}-label`}
          value={form.label}
          onChange={(e) => onChange('label', e.target.value)}
          className="input w-full"
        >
          {Object.entries(ADDRESS_LABELS).map(([value, label]) => (
            <option key={value} value={value}>{label}</option>
          ))}
        </select>
        {errors.label && <p className="text-xs text-red-400 mt-1">{errors.label}</p>}
      </div>

      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-recipient`}>Recipient Name *</label>
        <input
          id={`${idPrefix}-recipient`}
          className="input w-full"
          value={form.recipientName}
          onChange={(e) => onChange('recipientName', e.target.value)}
        />
        {errors.recipientName && <p className="text-xs text-red-400 mt-1">{errors.recipientName}</p>}
      </div>

      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-phone`}>Phone *</label>
        <input
          id={`${idPrefix}-phone`}
          className="input w-full"
          placeholder="+254..."
          value={form.phone}
          onChange={(e) => onChange('phone', e.target.value)}
        />
        {errors.phone && <p className="text-xs text-red-400 mt-1">{errors.phone}</p>}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-county`}>County *</label>
          <input
            id={`${idPrefix}-county`}
            className="input w-full"
            value={form.county}
            onChange={(e) => onChange('county', e.target.value)}
          />
          {errors.county && <p className="text-xs text-red-400 mt-1">{errors.county}</p>}
        </div>
        <div>
          <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-town`}>Town / City *</label>
          <input
            id={`${idPrefix}-town`}
            className="input w-full"
            value={form.town}
            onChange={(e) => onChange('town', e.target.value)}
          />
          {errors.town && <p className="text-xs text-red-400 mt-1">{errors.town}</p>}
        </div>
      </div>

      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-street`}>Street Address *</label>
        <input
          id={`${idPrefix}-street`}
          className="input w-full"
          value={form.streetAddress}
          onChange={(e) => onChange('streetAddress', e.target.value)}
        />
        {errors.streetAddress && <p className="text-xs text-red-400 mt-1">{errors.streetAddress}</p>}
      </div>

      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor={`${idPrefix}-directions`}>Additional Directions</label>
        <textarea
          id={`${idPrefix}-directions`}
          className="input w-full"
          rows={2}
          value={form.additionalDirections}
          onChange={(e) => onChange('additionalDirections', e.target.value)}
        />
      </div>

      {showDefaultToggle && (
        <label className="flex items-center gap-2 text-sm text-slate-300 cursor-pointer">
          <input
            type="checkbox"
            checked={Boolean(form.isDefault)}
            onChange={(e) => onChange('isDefault', e.target.checked)}
            className="rounded border-surface-border"
          />
          Set as default address
        </label>
      )}
    </div>
  );
}
