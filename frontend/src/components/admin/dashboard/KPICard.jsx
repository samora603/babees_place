import clsx from 'clsx';
import { formatCurrency } from '@/utils/helpers';
import { FiDollarSign, FiShoppingBag, FiPackage, FiUsers } from 'react-icons/fi';

const ICONS = {
  totalRevenue: FiDollarSign,
  totalOrders: FiShoppingBag,
  totalProducts: FiPackage,
  totalUsers: FiUsers,
};

const ACCENTS = {
  totalRevenue: { color: 'text-brand-400', bg: 'bg-brand-500/10' },
  totalOrders: { color: 'text-brand-500', bg: 'bg-brand-500/5' },
  totalProducts: { color: 'text-brand-500', bg: 'bg-brand-500/5' },
  totalUsers: { color: 'text-brand-500', bg: 'bg-brand-500/5' },
};

function formatKPIValue(value, format) {
  if (format === 'currency') return formatCurrency(value);
  return Number(value ?? 0).toLocaleString('en-KE');
}

/**
 * Reusable KPI card for the admin dashboard.
 * @param {{ kpi: import('@/models/dashboard').KPIValue, className?: string }} props
 */
export default function KPICard({ kpi, className = '' }) {
  const Icon = ICONS[kpi.key] || FiPackage;
  const accent = ACCENTS[kpi.key] || ACCENTS.totalProducts;

  return (
    <div
      className={clsx(
        'bg-[#111] p-6 rounded-2xl border border-brand-500/10 shadow-[0_4px_20px_rgba(0,0,0,0.3)]',
        'flex items-center gap-5 hover:border-brand-500/30 transition-all duration-300 group relative overflow-hidden',
        className,
      )}
    >
      <div className="absolute -right-4 -top-4 w-20 h-20 bg-brand-500/5 rounded-full blur-[20px] pointer-events-none group-hover:bg-brand-500/10 transition-colors" />
      <div className={clsx('w-14 h-14 rounded-xl flex items-center justify-center shrink-0 border border-brand-500/20', accent.bg)}>
        <Icon size={24} className={accent.color} aria-hidden />
      </div>
      <div className="relative z-10">
        <p className="text-[11px] font-semibold text-slate-400 uppercase tracking-widest mb-1">{kpi.label}</p>
        <p className={clsx('font-display font-bold text-3xl tracking-wide', accent.color)}>
          {formatKPIValue(kpi.value, kpi.format)}
        </p>
      </div>
    </div>
  );
}
