import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { adminService } from '@/services/adminService';
import { formatCurrency, formatDate } from '@/utils/helpers';
import OrderStatusBadge from '@/components/orders/OrderStatusBadge';
import Spinner from '@/components/ui/Spinner';
import Pagination from '@/components/ui/Pagination';
import Modal from '@/components/ui/Modal';
import Button from '@/components/ui/Button';
import toast from 'react-hot-toast';
import { ORDER_STATUSES } from '@/utils/constants';

export default function AdminOrders() {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [pages, setPages] = useState(1);
  const [statusFilter, setStatusFilter] = useState('');
  const [selected, setSelected] = useState(null);
  const [newStatus, setNewStatus] = useState('');
  const [note, setNote] = useState('');
  const [updating, setUpdating] = useState(false);

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

  const handleUpdateStatus = async () => {
    setUpdating(true);
    try {
      const { data } = await adminService.updateOrderStatus(selected.id, {
        status: newStatus,
        note,
      });

      if (data.error) throw data.error;

      toast.success('Order updated');
      setSelected(null);
      fetchOrders();
    } catch {
      toast.error('Update failed');
    } finally {
      setUpdating(false);
    }
  };

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-bold">Orders</h1>

      <select
        value={statusFilter}
        onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
        className="input max-w-xs"
      >
        <option value="">All statuses</option>
        {Object.entries(ORDER_STATUSES).map(([k, v]) => (
          <option key={k} value={k}>
            {v.label}
          </option>
        ))}
      </select>

      {loading ? (
        <Spinner />
      ) : (
        <table className="w-full">
          <thead>
            <tr>
              <th className="text-left p-2">ID</th>
              <th className="text-left p-2">User</th>
              <th className="text-left p-2">Total</th>
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
                  <div className="text-xs text-gray-400">
                    {o.profiles?.email}
                  </div>
                </td>

                <td className="p-2">{formatCurrency(o.total)}</td>

                <td className="p-2">
                  <OrderStatusBadge status={o.status} />
                </td>

                <td className="p-2">{formatDate(o.created_at)}</td>

                <td className="p-2 space-x-2">
                  <Link to={`/admin/orders/${o.id}`} className="text-sm text-brand-400 hover:underline">
                    View
                  </Link>
                  <button
                    type="button"
                    onClick={() => {
                      setSelected(o);
                      setNewStatus(o.status);
                      setNote(o.note || '');
                    }}
                    className="text-sm text-slate-300 hover:text-white"
                  >
                    Edit
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      <Pagination page={page} pages={pages} onPage={setPage} />

      <Modal isOpen={!!selected} onClose={() => setSelected(null)}>
        <h2 className="text-lg font-bold mb-4">Update Order</h2>

        <select
          value={newStatus}
          onChange={(e) => setNewStatus(e.target.value)}
          className="input w-full mb-3"
        >
          {Object.entries(ORDER_STATUSES).map(([k, v]) => (
            <option key={k} value={k}>
              {v.label}
            </option>
          ))}
        </select>

        <textarea
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Admin note (optional)"
          className="input w-full mb-4 min-h-[80px]"
        />

        <Button onClick={handleUpdateStatus} loading={updating}>
          Update
        </Button>
      </Modal>
    </div>
  );
}
