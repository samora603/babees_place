import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/context/AuthContext';
import { normalizePhone } from '@/utils/helpers';
import toast from 'react-hot-toast';
import Button from '@/components/ui/Button';

export default function Register() {
  const { signup } = useAuth();

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [loading, setLoading] = useState(false);

  const handleRegister = async (e) => {
    e.preventDefault();

    const trimmedEmail = email.trim();
    const trimmedName = fullName.trim();

    if (!trimmedName || !trimmedEmail || !phone || !password || !confirmPassword) {
      toast.error('Please fill in all fields');
      return;
    }

    if (password.length < 6) {
      toast.error('Password must be at least 6 characters');
      return;
    }

    if (password !== confirmPassword) {
      toast.error('Passwords do not match');
      return;
    }

    const formattedPhone = normalizePhone(phone);

    setLoading(true);

    try {
      const result = await signup(trimmedEmail, password, trimmedName, formattedPhone);
      if (result?.session) {
        toast.success('Account created successfully!');
      } else {
        toast.success('Account created! Check your email to confirm, then sign in.');
      }
    } catch (err) {
      console.error('REGISTER ERROR:', err);
      toast.error(err.message || 'Registration failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface text-white px-4">
      <div className="w-full max-w-md bg-white/5 border border-white/10 rounded-2xl p-8">
        <h2 className="text-2xl font-bold mb-6 text-center">
          Create Account
        </h2>

        <form onSubmit={handleRegister} className="space-y-4">
          <input
            type="text"
            placeholder="Full Name"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl"
            required
          />

          <input
            type="email"
            placeholder="Email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl"
            autoComplete="email"
            required
          />

          <input
            type="text"
            placeholder="Phone (07XXXXXXXX)"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl"
            required
          />

          <input
            type="password"
            placeholder="Password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl"
            autoComplete="new-password"
            required
          />

          <input
            type="password"
            placeholder="Confirm Password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            className="w-full px-4 py-3 bg-white/5 border border-white/10 rounded-xl"
            autoComplete="new-password"
            required
          />

          <Button type="submit" loading={loading} disabled={loading} className="w-full">
            Create Account
          </Button>
        </form>

        <p className="text-sm text-center mt-6 text-slate-400">
          Already have an account?{' '}
          <Link to="/login" className="text-brand-400">
            Login
          </Link>
        </p>
      </div>
    </div>
  );
}
