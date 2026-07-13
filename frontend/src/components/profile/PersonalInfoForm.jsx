import { useState, useEffect } from 'react';
import { useAuth } from '@/context/AuthContext';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function PersonalInfoForm() {
  const { user, profile, updateProfile } = useAuth();
  const [name, setName] = useState(profile?.full_name || '');
  const [email, setEmail] = useState(profile?.email || user?.email || '');
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    setName(profile?.full_name || '');
    setEmail(profile?.email || user?.email || '');
  }, [profile, user]);

  const handleSave = async (e) => {
    e.preventDefault();
    setSaving(true);
    try {
      await updateProfile({ full_name: name, email });
      toast.success('Personal information updated');
    } catch (err) {
      toast.error(err.message || 'Update failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <form onSubmit={handleSave} className="space-y-4">
      <div>
        <p className="text-sm text-slate-400">Phone (account)</p>
        <p className="font-semibold text-slate-100 mt-1">{profile?.phone || '—'}</p>
      </div>
      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="profile-name">Full Name</label>
        <input
          id="profile-name"
          type="text"
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Your name"
          className="input w-full"
        />
      </div>
      <div>
        <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="profile-email">Email</label>
        <input
          id="profile-email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="your@email.com"
          className="input w-full"
        />
      </div>
      <Button type="submit" loading={saving}>Save Personal Info</Button>
    </form>
  );
}
