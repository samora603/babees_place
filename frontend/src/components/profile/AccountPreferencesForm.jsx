import { useEffect, useState } from 'react';
import { customerProfileService } from '@/services/customerProfileService';
import { notificationPreferenceService } from '@/services/notificationPreferenceService';
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
    emailNotifications: true,
    orderUpdates: true,
    paymentUpdates: true,
  });

  useEffect(() => {
    let mounted = true;
    (async () => {
      setLoading(true);
      const [prefsResult, locationsResult, notifResult] = await Promise.all([
        customerProfileService.getPreferences(),
        orderService.getActivePickupLocations(),
        notificationPreferenceService.getNotificationPreferences(),
      ]);
      if (!mounted) return;

      if (prefsResult.error) {
        setError(prefsResult.error);
      }

      const prefs = prefsResult.data;
      const notif = notifResult.data;
      setForm({
        preferredFulfillment: prefs?.preferredFulfillment || '',
        preferredPickupLocationId: prefs?.preferredPickupLocationId || '',
        marketingEmails: notif?.marketingEmails ?? prefs?.marketingEmails ?? false,
        smsNotifications: notif?.smsEnabled ?? prefs?.smsNotifications ?? false,
        emailNotifications: notif?.emailEnabled ?? prefs?.emailNotifications ?? true,
        orderUpdates: notif?.orderUpdates ?? prefs?.orderUpdates ?? true,
        paymentUpdates: notif?.paymentUpdates ?? prefs?.paymentUpdates ?? true,
      });
      setPickupLocations(locationsResult.data || []);
      setLoading(false);
    })();
    return () => { mounted = false; };
  }, []);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);

    const [profileResult, notifResult] = await Promise.all([
      customerProfileService.upsertPreferences({
        preferredFulfillment: form.preferredFulfillment || null,
        preferredPickupLocationId: form.preferredPickupLocationId || null,
        marketingEmails: form.marketingEmails,
        smsNotifications: form.smsNotifications,
        emailNotifications: form.emailNotifications,
        orderUpdates: form.orderUpdates,
        paymentUpdates: form.paymentUpdates,
      }),
      notificationPreferenceService.upsertNotificationPreferences({
        emailEnabled: form.emailNotifications,
        smsEnabled: form.smsNotifications,
        inAppEnabled: true,
        pushEnabled: false,
        marketingEmails: form.marketingEmails,
        orderUpdates: form.orderUpdates,
        paymentUpdates: form.paymentUpdates,
      }),
    ]);

    setSaving(false);

    if (profileResult.error || notifResult.error) {
      toast.error(
        profileResult.error?.message
          || notifResult.error?.message
          || 'Could not save preferences',
      );
      return;
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
      description="Checkout defaults and notification channels."
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
          <legend className="text-sm text-slate-400 px-1">Notifications</legend>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.emailNotifications}
              onChange={(e) => setForm((f) => ({ ...f, emailNotifications: e.target.checked }))}
            />
            Email notifications
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.smsNotifications}
              onChange={(e) => setForm((f) => ({ ...f, smsNotifications: e.target.checked }))}
            />
            SMS notifications
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.orderUpdates}
              onChange={(e) => setForm((f) => ({ ...f, orderUpdates: e.target.checked }))}
            />
            Order updates
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.paymentUpdates}
              onChange={(e) => setForm((f) => ({ ...f, paymentUpdates: e.target.checked }))}
            />
            Payment updates
          </label>
          <label className="flex items-center gap-2 text-sm text-slate-300">
            <input
              type="checkbox"
              checked={form.marketingEmails}
              onChange={(e) => setForm((f) => ({ ...f, marketingEmails: e.target.checked }))}
            />
            Marketing emails
          </label>
        </fieldset>

        <Button type="submit" loading={saving}>Save Preferences</Button>
      </form>
    </ProfileSection>
  );
}
