import { useEffect, useState } from 'react';
import { customerProfileService } from '@/services/customerProfileService';
import { orderService } from '@/services/orderService';
import { DELIVERY_TYPES } from '@/utils/constants';
import ProfileSection from './ProfileSection';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';

export default function AccountPreferencesForm() {
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState(null);
  const [pickupLocations, setPickupLocations] = useState([]);
  const [form, setForm] = useState({
    preferredFulfillment: '',
    preferredPickupLocationId: '',
    marketingEmails: false,
    smsNotifications: false,
  });

  useEffect(() => {
    let mounted = true;
    (async () => {
      setLoading(true);
      const [prefsResult, locationsResult] = await Promise.all([
        customerProfileService.getPreferences(),
        orderService.getActivePickupLocations(),
      ]);
      if (!mounted) return;

      if (prefsResult.error) {
        setError(prefsResult.error);
      } else if (prefsResult.data) {
        setForm({
          preferredFulfillment: prefsResult.data.preferredFulfillment || '',
          preferredPickupLocationId: prefsResult.data.preferredPickupLocationId || '',
          marketingEmails: prefsResult.data.marketingEmails,
          smsNotifications: prefsResult.data.smsNotifications,
        });
      }
      setPickupLocations(locationsResult.data || []);
      setLoading(false);
    })();
    return () => { mounted = false; };
  }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    const { data, error: saveError } = await customerProfileService.upsertPreferences({
      preferredFulfillment: form.preferredFulfillment || null,
      preferredPickupLocationId: form.preferredPickupLocationId || null,
      marketingEmails: form.marketingEmails,
      smsNotifications: form.smsNotifications,
    });
    setSaving(false);

    if (saveError) {
      toast.error(saveError.message || 'Could not save preferences');
      return;
    }

    if (data) {
      setForm({
        preferredFulfillment: data.preferredFulfillment || '',
        preferredPickupLocationId: data.preferredPickupLocationId || '',
        marketingEmails: data.marketingEmails,
        smsNotifications: data.smsNotifications,
      });
    }
    toast.success('Preferences saved');
  };

  if (loading) {
    return (
      <ProfileSection title="Account Preferences" description="Customize your shopping experience.">
        <div className="flex justify-center py-8"><Spinner /></div>
      </ProfileSection>
    );
  }

  return (
    <ProfileSection
      id="preferences"
      title="Account Preferences"
      description="Defaults for checkout and future notifications (notifications not active yet)."
    >
      {error && (
        <p className="text-sm text-red-400">Unable to load preferences. You can still save new settings below.</p>
      )}

      <form onSubmit={handleSave} className="space-y-4">
        <div>
          <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="pref-fulfillment">Preferred fulfillment</label>
          <select
            id="pref-fulfillment"
            className="input w-full"
            value={form.preferredFulfillment}
            onChange={(e) => setForm((f) => ({ ...f, preferredFulfillment: e.target.value }))}
          >
            <option value="">No preference</option>
            {Object.entries(DELIVERY_TYPES).map(([key, { label }]) => (
              <option key={key} value={key}>{label}</option>
            ))}
          </select>
        </div>

        {form.preferredFulfillment === 'pickup' && (
          <div>
            <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="pref-pickup">Preferred pickup location</label>
            <select
              id="pref-pickup"
              className="input w-full"
              value={form.preferredPickupLocationId}
              onChange={(e) => setForm((f) => ({ ...f, preferredPickupLocationId: e.target.value }))}
            >
              <option value="">No preference</option>
              {pickupLocations.map((loc) => (
                <option key={loc.id} value={loc.id}>{loc.name} — {loc.building}</option>
              ))}
            </select>
          </div>
        )}

        <fieldset className="space-y-3 border border-brand-500/10 rounded-xl p-4">
          <legend className="text-sm text-slate-400 px-1">Future notifications (stored only)</legend>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.marketingEmails}
              onChange={(e) => setForm((f) => ({ ...f, marketingEmails: e.target.checked }))}
            />
            Marketing emails
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.smsNotifications}
              onChange={(e) => setForm((f) => ({ ...f, smsNotifications: e.target.checked }))}
            />
            SMS notifications
          </label>
        </fieldset>

        <Button type="submit" loading={saving}>Save Preferences</Button>
      </form>
    </ProfileSection>
  );
}
