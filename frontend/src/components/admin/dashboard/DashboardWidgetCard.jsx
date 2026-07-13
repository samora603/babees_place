import clsx from 'clsx';

/**
 * Shared card shell for dashboard widgets.
 */
export default function DashboardWidgetCard({ title, children, className = '' }) {
  return (
    <section
      className={clsx(
        'bg-[#111] rounded-2xl border border-brand-500/10 shadow-[0_4px_20px_rgba(0,0,0,0.3)] overflow-hidden',
        className,
      )}
    >
      <div className="px-5 py-4 border-b border-brand-500/10">
        <h2 className="font-display font-semibold text-sm uppercase tracking-widest text-slate-300">{title}</h2>
      </div>
      <div className="p-5">{children}</div>
    </section>
  );
}
