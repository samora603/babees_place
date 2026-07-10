import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { mapOrder } from '@/services/orderService';
import { formatCurrency, formatDateTime } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import { FiArrowLeft, FiClock, FiUser, FiSmartphone } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';

export default function AdminOrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    adminService.getOrder(id)
      .then(({ data }) => setOrder(mapOrder(data.data)))
      .finally(() => setLoading(false));
  }, [id]);

  if (loading) return <div className="flex justify-center py-24 bg-[#0B0B0B] min-h-full"><Spinner size="lg" /></div>;
  if (!order) return <p className="text-slate-400 p-8">Order not found.</p>;

  return (
    <div className="bg-[#0B0B0B] min-h-full pb-12 text-slate-200">
      <Link to="/admin/orders" className="inline-flex items-center gap-2 text-[10px] uppercase tracking-widest font-semibold text-slate-400 hover:text-brand-500 transition-colors mb-6 group">
        <FiArrowLeft className="group-hover:-translate-x-1 transition-transform" /> Return to Orders
      </Link>

      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6 border-b border-brand-500/10 pb-8 mb-8 relative">
        <div className="absolute top-0 right-0 w-40 h-40 bg-brand-500/5 rounded-full blur-[60px] pointer-events-none"></div>
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase flex items-center gap-3 mb-3">
             <GiBee className="text-brand-500/80" /> {order.orderNumber}
          </h1>
          <div className="flex flex-wrap items-center gap-3">
            <OrderStatusBadge status={order.orderStatus} />
            <span className="text-brand-500/30">•</span>
            <OrderStatusBadge status={order.paymentStatus} type="payment" />
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8 relative z-10">
        <div className="lg:col-span-1 space-y-8">
          <div className="bg-[#111] p-6 rounded-2xl border border-brand-500/10 shadow-[0_10px_30px_rgba(0,0,0,0.5)]">
            <h2 className="font-display font-semibold text-sm text-white uppercase tracking-widest flex items-center gap-2 mb-5 border-b border-brand-500/10 pb-3">
              <span className="w-1.5 h-1.5 rounded-full bg-brand-500"></span> Client Profile
            </h2>
            <div className="space-y-4">
               <div className="flex items-start gap-4">
                  <div className="w-8 h-8 rounded shrink-0 bg-[#0A0A0A] border border-brand-500/20 flex items-center justify-center text-brand-500"><FiUser size={14} /></div>
                  <div>
                     <p className="text-[10px] uppercase tracking-widest text-slate-500 font-semibold mb-1">Identity</p>
                     <p className="text-sm font-medium text-white">{order.user?.name || order.profiles?.full_name || 'Unknown'}</p>
                     <p className="text-xs text-slate-500">{order.profiles?.email}</p>
                  </div>
               </div>
               {order.customerPhone && (
                 <div className="flex items-start gap-4">
                    <div className="w-8 h-8 rounded shrink-0 bg-[#0A0A0A] border border-brand-500/20 flex items-center justify-center text-brand-500"><FiSmartphone size={14} /></div>
                    <div>
                       <p className="text-[10px] uppercase tracking-widest text-slate-500 font-semibold mb-1">Contact</p>
                       <p className="text-sm font-mono text-slate-300">{order.customerPhone}</p>
                    </div>
                 </div>
               )}
               <div className="flex items-start gap-4">
                  <div className="w-8 h-8 rounded shrink-0 bg-[#0A0A0A] border border-brand-500/20 flex items-center justify-center text-brand-500"><FiClock size={14} /></div>
                  <div>
                     <p className="text-[10px] uppercase tracking-widest text-slate-500 font-semibold mb-1">Timestamp</p>
                     <p className="text-xs font-mono text-slate-400 tracking-wider">{formatDateTime(order.createdAt)}</p>
                  </div>
               </div>
               {order.note && (
                 <div className="pt-2 border-t border-brand-500/10">
                   <p className="text-[10px] uppercase tracking-widest text-slate-500 font-semibold mb-1">Note</p>
                   <p className="text-sm text-slate-300">{order.note}</p>
                 </div>
               )}
            </div>
          </div>
        </div>

        <div className="lg:col-span-2">
          <div className="bg-[#111] p-6 sm:p-8 rounded-2xl border border-brand-500/10 shadow-[0_10px_30px_rgba(0,0,0,0.5)] h-full">
            <h2 className="font-display font-semibold text-sm text-white uppercase tracking-widest flex items-center gap-2 mb-6 border-b border-brand-500/10 pb-4">
              <span className="w-1.5 h-1.5 rounded-full bg-brand-500"></span> Order Items
            </h2>
            <div className="space-y-4">
              {order.items?.map((item) => (
                <div key={item.id} className="flex items-center justify-between p-4 rounded-xl border border-surface-border bg-[#0A0A0A] hover:border-brand-500/30 transition-colors group">
                  <div className="flex items-center gap-4">
                     <div className="w-12 h-12 rounded-lg border border-brand-500/10 bg-[#111] overflow-hidden shrink-0 group-hover:border-brand-500/30 transition-colors">
                         <img src={item.image || '/placeholder.png'} alt={item.name} className="w-full h-full object-cover opacity-90 group-hover:opacity-100 transition-opacity" />
                     </div>
                     <div>
                        <p className="font-medium text-white group-hover:text-brand-400 transition-colors tracking-wide text-sm">{item.name}</p>
                        <p className="text-xs text-slate-500 font-mono mt-1">QTY: {item.quantity} × {formatCurrency(item.price)}</p>
                     </div>
                  </div>
                  <span className="font-display font-medium text-brand-400 tracking-wide">{formatCurrency(item.price * item.quantity)}</span>
                </div>
              ))}
              <div className="border-t border-brand-500/20 pt-6 mt-6">
                <div className="flex justify-between items-center text-lg">
                  <span className="font-display font-bold text-white uppercase tracking-widest text-sm">Total</span>
                  <span className="font-display font-bold text-xl text-brand-500 drop-shadow-[0_0_8px_rgba(212,175,55,0.4)]">{formatCurrency(order.totalAmount)}</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
