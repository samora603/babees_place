import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useAuth } from '@/context/AuthContext';
import toast from 'react-hot-toast';
import Button from '@/components/ui/Button';

export default function Login() {
  const { login } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [formLoading, setFormLoading] = useState(false);

  const handleLogin = async (e) => {
    e.preventDefault();

    const trimmedEmail = email.trim();
    if (!trimmedEmail || !password) {
      toast.error('Please fill in all fields');
      return;
    }

    setFormLoading(true);

    try {
      await login(trimmedEmail, password);
      toast.success('Welcome back!');
    } catch (err) {
      console.error(err);
      toast.error(err.message || 'Login failed');
    } finally {
      setFormLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface text-white px-4">
      <div className="w-full max-w-md bg-white/5 border border-white/10 rounded-2xl p-8">
        <h2 className="text-2xl font-bold mb-6 text-center">
          Login to Babis Place
        </h2>

        <form onSubmit={handleLogin} className="space-y-5">
          <div>
            <label htmlFor="login-email" className="text-sm text-slate-300">
              Email
            </label>
            <input
              id="login-email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full mt-1 px-4 py-3 bg-white/5 border border-white/10 rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50"
              placeholder="you@example.com"
              required
            />
          </div>

          <div>
            <label htmlFor="login-password" className="text-sm text-slate-300">
              Password
            </label>
            <input
              id="login-password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full mt-1 px-4 py-3 bg-white/5 border border-white/10 rounded-xl outline-none focus-visible:ring-2 focus-visible:ring-brand-500/50"
              placeholder="••••••••"
              required
            />
          </div>

          <Button
            type="submit"
            loading={formLoading}
            disabled={formLoading}
            className="w-full"
          >
            Sign In
          </Button>
        </form>

        <p className="text-sm text-center mt-6 text-slate-400">
          Don’t have an account?{' '}
          <Link to="/register" className="text-brand-400 hover:underline">
            Sign up
          </Link>
        </p>
      </div>
    </div>
  );
}
