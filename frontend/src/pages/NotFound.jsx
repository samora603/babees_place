import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <div className="min-h-[70vh] flex flex-col items-center justify-center text-center px-4">
      <h1 className="font-display font-extrabold text-8xl text-brand-500/30 mb-2">404</h1>
      <h2 className="font-display font-bold text-3xl text-white mb-4">Page Not Found</h2>
      <p className="text-slate-400 mb-8 max-w-sm">The page you're looking for doesn't exist or has been moved.</p>
      <Link to="/" className="btn-primary">Go Home</Link>
    </div>
  );
}
