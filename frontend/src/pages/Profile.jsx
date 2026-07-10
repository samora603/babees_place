import { useState, useEffect } from 'react';
import { useAuth } from '@/context/AuthContext';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function Profile() {
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
      toast.success('Profile updated');
    } catch (err) {
      toast.error(err.message || 'Update failed');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="section-container py-10 max-w-2xl">
      <h1 className="font-display font-bold text-3xl mb-8">My Profile</h1>

      <div className="card p-6 space-y-6">
        <div>
          <p className="text-sm text-slate-400">Phone (cannot change)</p>
          <p className="font-semibold text-slate-100 mt-1">{profile?.phone || '—'}</p>
        </div>

        <form onSubmit={handleSave} className="space-y-4">
          <div>
            <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="profile-name">Full Name</label>
            <input id="profile-name" type="text" value={name} onChange={(e) => setName(e.target.value)} placeholder="Your name (optional)" className="input" />
          </div>
          <div>
            <label className="text-sm text-slate-400 mb-1.5 block" htmlFor="profile-email">Email (optional)</label>
            <input id="profile-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="your@email.com" className="input" />
          </div>
          <Button type="submit" loading={saving}>Save Changes</Button>
        </form>
      </div>
    </div>
  );
}
