import { Link } from 'react-router-dom';
import { FiZap } from 'react-icons/fi';

/**
 * Cart sidebar banner when express checkout is available.
 */
export default function ExpressCheckoutBanner({ summary }) {
  if (!summary) return null;

  return (
    <div className="mb-4 p-4 rounded-xl border border-brand-500/25 bg-brand-500/5">
      <div className="flex items-start gap-3">
        <FiZap className="text-brand-400 shrink-0 mt-0.5" size={18} />
        <div className="flex-1 min-w-0">
          <p className="text-sm font-medium text-brand-300">Express checkout available</p>
          <p className="text-xs text-slate-400 mt-1">{summary}</p>
          <Link
            to="/checkout"
            className="inline-block text-xs text-brand-400 hover:underline mt-2"
          >
            Checkout with saved details →
          </Link>
        </div>
      </div>
    </div>
  );
}
