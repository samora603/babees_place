import { GiBee } from 'react-icons/gi';

export default function DashboardPageHeader({
  title = 'Command Center',
  subtitle = 'Executive overview and analytics.',
}) {
  return (
    <div className="flex items-center gap-4 border-b border-brand-500/20 pb-6 mb-8 relative">
      <div className="absolute top-0 right-0 w-64 h-64 bg-brand-500/5 rounded-full blur-[80px] pointer-events-none" />
      <GiBee className="text-brand-500 text-4xl opacity-80" aria-hidden />
      <div>
        <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase">{title}</h1>
        <p className="text-sm text-slate-400 mt-1 font-light tracking-wide">{subtitle}</p>
      </div>
    </div>
  );
}
