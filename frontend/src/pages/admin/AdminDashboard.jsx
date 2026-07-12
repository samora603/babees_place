import { useEffect, useState } from 'react';
import { adminService } from '@/services/adminService';
import { formatCurrency } from '@/utils/helpers';
import { FiShoppingBag, FiPackage, FiUsers, FiDollarSign, FiAlertCircle } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';
import { AreaChart, Area, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from 'recharts';
import Spinner from '@/components/ui/Spinner';

export default function AdminDashboard() {
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    adminService.getStats().then(({ data }) => setStats(data.data)).finally(() => setLoading(false));
  }, []);

  if (loading) return <div className="flex justify-center py-20 bg-[#0B0B0B] min-h-full"><Spinner size="lg" /></div>;

  const StatCard = ({ icon: Icon, label, value, colorClass = 'text-brand-500', bgClass = 'bg-brand-500/10' }) => (
    <div className="bg-[#111] p-6 rounded-2xl border border-brand-500/10 shadow-[0_4px_20px_rgba(0,0,0,0.3)] flex items-center gap-5 hover:border-brand-500/30 transition-all duration-300 group relative overflow-hidden">
      <div className="absolute -right-4 -top-4 w-20 h-20 bg-brand-500/5 rounded-full blur-[20px] pointer-events-none group-hover:bg-brand-500/10 transition-colors"></div>
      <div className={`w-14 h-14 rounded-xl flex items-center justify-center shrink-0 ${bgClass} border border-brand-500/20`}>
        <Icon size={24} className={colorClass} />
      </div>
      <div className="relative z-10">
        <p className="text-[11px] font-semibold text-slate-400 uppercase tracking-widest mb-1">{label}</p>
        <p className={`font-display font-bold text-3xl tracking-wide ${colorClass}`}>{value}</p>
      </div>
    </div>
  );

  return (
    <div className="space-y-8 bg-[#0B0B0B] min-h-full text-slate-200">
      <div className="flex items-center gap-4 border-b border-brand-500/20 pb-6 mb-8 relative">
        <div className="absolute top-0 right-0 w-64 h-64 bg-brand-500/5 rounded-full blur-[80px] pointer-events-none"></div>
        <GiBee className="text-brand-500 text-4xl opacity-80" />
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase">Command Center</h1>
          <p className="text-sm text-slate-400 mt-1 font-light tracking-wide">Executive overview and analytics.</p>
        </div>
      </div>

      {/* Stat cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-6">
  <StatCard icon={FiDollarSign} label="Total Revenue" value={formatCurrency(stats.totalRevenue ?? 0)} colorClass="text-brand-400" bgClass="bg-brand-500/10" />
  <StatCard icon={FiShoppingBag} label="Total Orders"  value={(stats.totalOrders ?? 0).toLocaleString()} colorClass="text-brand-500" bgClass="bg-brand-500/5" />
  <StatCard icon={FiPackage}     label="Products"      value={(stats.totalProducts ?? 0).toLocaleString()} colorClass="text-brand-500" bgClass="bg-brand-500/5" />
  <StatCard icon={FiUsers}       label="Clients"     value={(stats.totalUsers ?? 0).toLocaleString()} colorClass="text-brand-500" bgClass="bg-brand-500/5" />
      </div>

      {/* Low stock alert */}
      {stats.lowStockCount > 0 && (
        <div className="flex items-center gap-4 bg-[#111] border border-brand-500/30 rounded-xl px-5 py-4 text-brand-300 text-sm shadow-[0_0_15px_rgba(212,175,55,0.1)]">
          <FiAlertCircle className="text-brand-500 text-lg shrink-0" /> 
          <span className="font-light tracking-wide">
            Attention: <strong className="font-semibold text-brand-400">{stats.lowStockCount} piece{stats.lowStockCount > 1 ? 's' : ''}</strong> require inventory replenishment. Review the Inventory collection.
          </span>
        </div>
      )}

      {/* Revenue chart */}
      <div className="bg-[#111] p-8 rounded-2xl border border-brand-500/10 shadow-[0_10px_40px_rgba(0,0,0,0.5)]">
        <h2 className="font-display font-semibold text-lg text-white uppercase tracking-widest mb-8 flex items-center gap-3">
          <span className="w-1.5 h-1.5 rounded-full bg-brand-500"></span> Financial Performance (7 Days)
        </h2>
        <div className="h-[300px] w-full">
          <ResponsiveContainer width="100%" height="100%">
            <AreaChart data={stats.revenueByDay}>
              <defs>
                <linearGradient id="revenueGrad" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="5%" stopColor="#D4AF37" stopOpacity={0.4} />
                  <stop offset="95%" stopColor="#D4AF37" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke="rgba(212,175,55,0.1)" vertical={false} />
              <XAxis dataKey="_id" tick={{ fill: '#94a3b8', fontSize: 12 }} axisLine={{ stroke: 'rgba(212,175,55,0.2)' }} tickLine={false} dy={10} />
              <YAxis tickFormatter={(v) => `KES ${v.toLocaleString()}`} tick={{ fill: '#94a3b8', fontSize: 12 }} width={80} axisLine={{ stroke: 'rgba(212,175,55,0.2)' }} tickLine={false} dx={-10} />
              <Tooltip 
                contentStyle={{ background: '#0A0A0A', border: '1px solid rgba(212,175,55,0.3)', borderRadius: 12, boxShadow: '0 10px 30px rgba(0,0,0,0.8)' }} 
                itemStyle={{ color: '#D4AF37', fontWeight: 600 }}
                labelStyle={{ color: '#f1f5f9', marginBottom: 4 }} 
                formatter={(v) => [formatCurrency(v), 'Revenue']} 
                cursor={{ stroke: 'rgba(212,175,55,0.4)', strokeWidth: 1, strokeDasharray: '4 4' }}
              />
              <Area type="monotone" dataKey="revenue" stroke="#D4AF37" fill="url(#revenueGrad)" strokeWidth={3} activeDot={{ r: 6, fill: '#D4AF37', stroke: '#0B0B0B', strokeWidth: 2 }} />
            </AreaChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}
