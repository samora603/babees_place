import { GiBee } from 'react-icons/gi';

export default function DashboardEmptyState({
  title = 'No activity yet',
  description = 'KPIs will appear once you have products, clients, and orders.',
}) {
  return (
    <div className="card p-10 text-center border border-brand-500/10 bg-[#111]">
      <GiBee className="text-brand-500 text-4xl mx-auto mb-4 opacity-80" />
      <h2 className="font-display font-semibold text-lg text-white mb-2">{title}</h2>
      <p className="text-sm text-slate-400 max-w-md mx-auto">{description}</p>
    </div>
  );
}
