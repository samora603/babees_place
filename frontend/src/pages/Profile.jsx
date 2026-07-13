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

      <section className="card p-6">
        <h2 className="font-display font-semibold text-xl text-white mb-4">Personal Information</h2>
        <PersonalInfoForm />
      </section>

      <AddressBook />
      <AccountPreferencesForm />
    </div>
  );
}
