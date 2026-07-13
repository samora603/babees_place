import Button from '@/components/ui/Button';
import { FiAlertCircle } from 'react-icons/fi';

export default function DashboardErrorState({
  message = 'Unable to load dashboard data.',
  onRetry,
}) {
  return (
    <div className="card p-10 text-center border border-red-500/20 bg-[#111]">
      <FiAlertCircle className="text-red-400 text-3xl mx-auto mb-4" />
      <h2 className="font-display font-semibold text-lg text-white mb-2">Dashboard unavailable</h2>
      <p className="text-sm text-slate-400 mb-6">{message}</p>
      {onRetry && (
        <Button variant="secondary" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  );
}
