import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { formatCurrency, formatDate } from '@/utils/helpers';
import { getAllowedNextStatuses, canAdminCancel } from '@/utils/orderStatus';
import { PAYMENT_STATUSES, ORDER_STATUSES } from '@/utils/constants';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import Pagination from '@/components/ui/Pagination';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';

export default function AdminOrders() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pages, setPages] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [selected, setSelected] = useState(null);
  const [newStatus, setNewStatus] = useState('');
  const [newPaymentStatus, setNewPaymentStatus] = useState('');
  const [note, setNote] = useState('');
  const [updating, setUpdating] = useState(false);
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);

  const fetchOrders = () => {
    setLoading(true);
    adminService
      .getOrders({ page, limit: 15, ...(statusFilter && { status: statusFilter }) })
      .then(({ data }) => {
        setOrders(data.data || []);
        setPages(Math.ceil((data.total || 0) / 15));
      })
      .catch(() => toast.error('Failed to load orders'))
      .finally(() => setLoading(false));
  };

  useEffect(fetchOrders, [page, statusFilter]);

  const openEdit = (order) => {
    setSelected(order);
    setNewStatus(order.status);
    setNewPaymentStatus(order.payment_status || 'pending');
    setNote(order.note || '');
    setShowCancelConfirm(false);
  };

  const nextStatuses = selected
    ? getAllowedNextStatuses(selected.status, selected.delivery_type)
    : [];
  const showCancelOption = selected && canAdminCancel(selected.status);

  const handleUpdateStatus = async () => {
    if (!selected) return;
    if (newStatus === 'cancelled') {
      setShowCancelConfirm(true);
      return;
    }
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderStatus(selected.id, { status: newStatus, note });
      if (data.error) throw data.error;
      toast.success('Order updated');
      setSelected(null);
      fetchOrders();
    } catch (err) {
      toast.error(err.message || 'Update failed');
    } finally {
      setUpdating(false);
    }
  };

  const handleConfirmCancel = async () => {
    if (!selected) return;
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderStatus(selected.id, { status: 'cancelled', note });
      if (data.error) throw data.error;
      toast.success('Order cancelled — stock restored');
      setSelected(null);
      setShowCancelConfirm(false);
      fetchOrders();
    } catch (err) {
      toast.error(err.message || 'Cancel failed');
    } finally {
      setUpdating(false);
    }
  };

  const handleUpdatePayment = async () => {
    if (!selected) return;
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderPaymentStatus(selected.id, {
        paymentStatus: newPaymentStatus,
        note,
      });
      if (data.error) throw data.error;
      toast.success('Payment status updated');
      fetchOrders();
    } catch (err) {
      toast.error(err.message || 'Payment update failed');
    } finally {
      setUpdating(false);
    }
  };

  return (
    <div className="space-y-6 p-6">
      <h1 className="text-2xl font-bold">Orders</h1>

      <select
        value={statusFilter}
        onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
        className="input max-w-xs"
      >
        <option value="">All statuses</option>
        {Object.entries(ORDER_STATUSES).map(([k, v]) => (
          <option key={k} value={k}>{v.label}</option>
        ))}
      </select>

      {loading ? (
        <Spinner />
      ) : orders.length === 0 ? (
        <div className="card p-10 text-center text-slate-400">No orders found.</div>
      ) : (
        <table className="w-full">
          <thead>
            <tr>
              <th className="text-left p-2">ID</th>
              <th className="text-left p-2">User</th>
              <th className="text-left p-2">Total</th>
              <th className="text-left p-2">Fulfillment</th>
              <th className="text-left p-2">Payment</th>
              <th className="text-left p-2">Status</th>
              <th className="text-left p-2">Date</th>
              <th className="text-left p-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {orders.map((o) => (
              <tr key={o.id} className="border-t border-surface-border">
                <td className="p-2">
                  <Link to={`/admin/orders/${o.id}`} className="text-brand-400 hover:underline">
                    #{String(o.id).slice(0, 8)}
                  </Link>
                </td>
                <td className="p-2">
                  {o.profiles?.full_name || 'Unknown'}
                  <div className="text-xs text-gray-400">{o.profiles?.email}</div>
                </td>
                <td className="p-2">{formatCurrency(o.total)}</td>
                <td className="p-2 text-xs text-slate-400 capitalize">{o.delivery_type || '—'}</td>
                <td className="p-2">
                  <div className="flex flex-col gap-1">
                    <OrderStatusBadge status={o.payment_status || 'pending'} type="payment" />
                    <span className="text-[10px] uppercase tracking-wide text-slate-500">
                      {(o.payment_method || 'cod').replace('_', ' ')}
                      {o.mpesa_receipt_number ? ` · ${o.mpesa_receipt_number}` : ''}
                    </span>
                  </div>
                </td>
                <td className="p-2"><OrderStatusBadge status={o.status} /></td>
                <td className="p-2">{formatDate(o.created_at)}</td>
                <td className="p-2 space-x-2">
                  <Link to={`/admin/orders/${o.id}`} className="text-sm text-brand-400 hover:underline">View</Link>
                  <button type="button" onClick={() => openEdit(o)} className="text-sm text-slate-300 hover:text-white">Edit</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <Pagination page={page} pages={pages} onPage={setPage} />

      <Modal isOpen={!!selected && !showCancelConfirm} onClose={() => setSelected(null)} title="Update Order">
        {selected && (
          <div className="space-y-4">
            <p className="text-sm text-slate-400">Order #{String(selected.id).slice(0, 8)} · {selected.delivery_type || 'legacy'}</p>

            <div>
              <label className="text-sm text-slate-400 block mb-1">Next status</label>
              <select value={newStatus} onChange={(e) => setNewStatus(e.target.value)} className="input w-full">
                <option value={selected.status}>Keep: {selected.status}</option>
                {nextStatuses.map((s) => (
                  <option key={s} value={s}>{s.replace(/_/g, ' ')}</option>
                ))}
                {showCancelOption && <option value="cancelled">Cancel order (restores stock)</option>}
              </select>
            </div>

            <div>
              <label className="text-sm text-slate-400 block mb-1">Payment status</label>
              <select value={newPaymentStatus} onChange={(e) => setNewPaymentStatus(e.target.value)} className="input w-full">
                {Object.entries(PAYMENT_STATUSES).map(([k, v]) => (
                  <option key={k} value={k}>{v.label}</option>
                ))}
              </select>
            </div>

            <textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Admin note" className="input w-full min-h-[80px]" />

            <div className="flex gap-3">
              <Button onClick={handleUpdateStatus} loading={updating}>Update Status</Button>
              <Button variant="secondary" onClick={handleUpdatePayment} loading={updating}>Update Payment</Button>
            </div>
          </div>
        )}
      </Modal>

      <Modal isOpen={showCancelConfirm} onClose={() => setShowCancelConfirm(false)} title="Confirm Cancellation" size="sm">
        <p className="text-sm text-slate-300 mb-4">
          Cancel this order? Inventory will be restored automatically via <code>cancel_order()</code>.
        </p>
        <div className="flex gap-3">
          <Button variant="secondary" onClick={() => setShowCancelConfirm(false)}>Back</Button>
          <Button loading={updating} onClick={handleConfirmCancel} className="bg-red-600 hover:bg-red-500">Confirm Cancel</Button>
        </div>
      </Modal>
    </div>
  );
}
