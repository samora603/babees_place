import { useEffect, useState } from 'react';
import { useParams, Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { mapOrder } from '@/services/orderService';
import { formatCurrency, formatDateTime } from '@/utils/helpers';
import { getAllowedNextStatuses, canAdminCancel } from '@/utils/orderStatus';
import { PAYMENT_STATUSES } from '@/utils/constants';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import OrderStatusTimeline from '@/components/orders/OrderStatusTimeline';
import FulfillmentDetails from '@/components/orders/FulfillmentDetails';
import PaymentDetailsCard from '@/components/orders/PaymentDetailsCard';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import Spinner from '@/components/ui/Spinner';
import toast from 'react-hot-toast';
import { FiArrowLeft } from 'react-icons/fi';
import { GiBee } from 'react-icons/gi';
import { paymentService } from '@/services/paymentService';

export default function AdminOrderDetail() {
  const { id } = useParams();
  const [order, setOrder] = useState(null);
  const [payment, setPayment] = useState(null);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [cancelConfirm, setCancelConfirm] = useState(false);
  const [newStatus, setNewStatus] = useState('');
  const [newPaymentStatus, setNewPaymentStatus] = useState('');
  const [note, setNote] = useState('');
  const [updating, setUpdating] = useState(false);

  const loadOrder = () => {
    setLoading(true);
    Promise.all([
      adminService.getOrder(id),
      paymentService.getLatestPaymentForOrder(id).catch(() => null),
    ])
      .then(([orderRes, latestPayment]) => {
        setOrder(mapOrder(orderRes.data.data));
        setPayment(latestPayment);
      })
      .finally(() => setLoading(false));
  };

  useEffect(loadOrder, [id]);

  const nextStatuses = order ? getAllowedNextStatuses(order.status, order.deliveryType) : [];
  const showCancel = order && canAdminCancel(order.status);

  const openModal = () => {
    setNewStatus(order.status);
    setNewPaymentStatus(order.paymentStatus || 'pending');
    setNote(order.note || '');
    setCancelConfirm(false);
    setModalOpen(true);
  };

  const handleUpdate = async () => {
    if (newStatus === 'cancelled') {
      setCancelConfirm(true);
      return;
    }
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderStatus(id, { status: newStatus, note });
      if (data.error) throw data.error;
      toast.success('Status updated');
      setModalOpen(false);
      loadOrder();
    } catch (err) {
      toast.error(err.message || 'Update failed');
    } finally {
      setUpdating(false);
    }
  };

  const handleCancel = async () => {
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderStatus(id, { status: 'cancelled', note });
      if (data.error) throw data.error;
      toast.success('Order cancelled');
      setModalOpen(false);
      setCancelConfirm(false);
      loadOrder();
    } catch (err) {
      toast.error(err.message || 'Cancel failed');
    } finally {
      setUpdating(false);
    }
  };

  const handlePaymentUpdate = async () => {
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderPaymentStatus(id, {
        paymentStatus: newPaymentStatus,
        note,
      });
      if (data.error) throw data.error;
      toast.success('Payment updated');
      loadOrder();
    } catch (err) {
      toast.error(err.message || 'Payment update failed');
    } finally {
      setUpdating(false);
    }
  };

  if (loading) return <div className="flex justify-center py-24 bg-[#0B0B0B] min-h-full"><Spinner size="lg" /></div>;
  if (!order) return <p className="text-slate-400 p-8">Order not found.</p>;

  return (
    <div className="bg-[#0B0B0B] min-h-full pb-12 text-slate-200 p-6">
      <Link to="/admin/orders" className="inline-flex items-center gap-2 text-[10px] uppercase tracking-widest font-semibold text-slate-400 hover:text-brand-500 transition-colors mb-6 group">
        <FiArrowLeft className="group-hover:-translate-x-1 transition-transform" /> Return to Orders
      </Link>

      <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between gap-6 border-b border-brand-500/10 pb-8 mb-8">
        <div>
          <h1 className="font-display font-bold text-3xl text-white tracking-wide uppercase flex items-center gap-3 mb-3">
            <GiBee className="text-brand-500/80" /> {order.orderNumber}
          </h1>
          <div className="flex flex-wrap items-center gap-3">
            <OrderStatusBadge status={order.orderStatus} />
            <OrderStatusBadge status={order.paymentStatus} type="payment" />
          </div>
        </div>
        {order.status !== 'cancelled' && order.status !== 'delivered' && (
          <Button onClick={openModal}>Update Order</Button>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-1 space-y-6">
          <div className="bg-[#111] p-6 rounded-2xl border border-brand-500/10">
            <h2 className="font-semibold text-sm uppercase tracking-widest mb-4">Client</h2>
            <div className="space-y-3 text-sm">
              <p className="text-white">{order.user?.name || 'Unknown'}</p>
              <p className="text-slate-500">{order.profiles?.email}</p>
              {order.customerPhone && <p className="font-mono text-slate-400">{order.customerPhone}</p>}
              <p className="text-xs text-slate-500">{formatDateTime(order.createdAt)}</p>
            </div>
          </div>
          <OrderStatusTimeline status={order.status} deliveryType={order.deliveryType} />
          <FulfillmentDetails order={order} />
          <PaymentDetailsCard order={order} payment={payment} />
        </div>

        <div className="lg:col-span-2 bg-[#111] p-6 rounded-2xl border border-brand-500/10">
          <h2 className="font-semibold mb-4">Items</h2>
          <div className="space-y-3">
            {order.items?.map((item) => (
              <div key={item.id} className="flex justify-between p-4 rounded-xl border border-surface-border bg-[#0A0A0A]">
                <div className="flex gap-3">
                  <img src={item.image} alt="" className="w-12 h-12 rounded-lg object-cover" />
                  <div>
                    <p className="font-medium">{item.name}</p>
                    <p className="text-xs text-slate-500">Qty: {item.quantity}</p>
                  </div>
                </div>
                <span className="text-brand-400 font-semibold">{formatCurrency(item.price * item.quantity)}</span>
              </div>
            ))}
          </div>
          <div className="border-t border-brand-500/20 pt-4 mt-4 flex justify-between font-bold">
            <span>Total</span>
            <span className="text-brand-400">{formatCurrency(order.totalAmount)}</span>
          </div>
          {order.note && (
            <p className="text-sm text-slate-400 mt-4 border-t border-surface-border pt-4">Admin note: {order.note}</p>
          )}
        </div>
      </div>

      <Modal isOpen={modalOpen && !cancelConfirm} onClose={() => setModalOpen(false)} title="Update Order">
        <div className="space-y-4">
          <select value={newStatus} onChange={(e) => setNewStatus(e.target.value)} className="input w-full">
            <option value={order.status}>Keep: {order.status}</option>
            {nextStatuses.map((s) => <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>)}
            {showCancel && <option value="cancelled">Cancel (restores stock)</option>}
          </select>
          <select value={newPaymentStatus} onChange={(e) => setNewPaymentStatus(e.target.value)} className="input w-full">
            {Object.entries(PAYMENT_STATUSES).map(([k, v]) => (
              <option key={k} value={k}>{v.label}</option>
            ))}
          </select>
          <textarea value={note} onChange={(e) => setNote(e.target.value)} className="input w-full min-h-[80px]" placeholder="Admin note" />
          <div className="flex gap-3">
            <Button onClick={handleUpdate} loading={updating}>Save Status</Button>
            <Button variant="secondary" onClick={handlePaymentUpdate} loading={updating}>Save Payment</Button>
          </div>
        </div>
      </Modal>

      <Modal isOpen={cancelConfirm} onClose={() => setCancelConfirm(false)} title="Confirm Cancel" size="sm">
        <p className="text-sm text-slate-300 mb-4">Cancel order and restore inventory?</p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setCancelConfirm(false)}>Back</Button>
          <Button loading={updating} onClick={handleCancel} className="bg-red-600 hover:bg-red-500">Confirm</Button>
        </div>
      </Modal>
    </div>
  );
}
