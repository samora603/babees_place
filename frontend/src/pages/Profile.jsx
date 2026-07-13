import { Link } from 'react-router-dom';
import PersonalInfoForm from '@/components/profile/PersonalInfoForm';
import AddressBook from '@/components/profile/AddressBook';
import AccountPreferencesForm from '@/components/profile/AccountPreferencesForm';

export default function Profile() {
  return (
    <div className="section-container py-10 max-w-3xl space-y-8">
      <div>
        <h1 className="font-display font-bold text-3xl mb-2">My Account</h1>
        <p className="text-slate-400 text-sm">Manage your personal details, addresses, and preferences.</p>
      </div>

      <Link
        to="/rewards"
        className="block card p-5 border border-brand-500/20 hover:border-brand-500/40 transition-colors"
      >
        <h2 className="font-display font-semibold text-lg text-brand-400">Rewards dashboard</h2>
        <p className="text-sm text-slate-400 mt-1">Points, coupons, referrals, and gift cards →</p>
      </Link>

      <section className="card p-6">
        <h2 className="font-display font-semibold text-xl text-white mb-4">Personal Information</h2>
        <PersonalInfoForm />
      </section>

      <AddressBook />
      <AccountPreferencesForm />
    </div>
  );
}
