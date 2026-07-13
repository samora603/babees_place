import Spinner from '@/components/ui/Spinner';

export default function DashboardLoadingState({ message = 'Loading dashboard…' }) {
  return (
    <div className="flex flex-col items-center justify-center py-20 bg-[#0B0B0B] min-h-full gap-4">
      <Spinner size="lg" />
      <p className="text-sm text-slate-400">{message}</p>
    </div>
  );
}
