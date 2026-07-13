import { useCallback, useEffect, useState } from 'react';
import { notificationService } from '@/services/notificationService';
import NotificationItem from './NotificationItem';
import Spinner from '@/components/ui/Spinner';
import Button from '@/components/ui/Button';

const FILTERS = [
  { id: 'active', label: 'Inbox', status: 'active' },
  { id: 'unread', label: 'Unread', status: 'unread' },
  { id: 'orders', label: 'Orders', category: 'orders' },
  { id: 'payments', label: 'Payments', category: 'payments' },
  { id: 'archived', label: 'Archived', status: 'archived' },
];

/**
 * Lazy-friendly notification list with filter + pagination.
 */
export default function NotificationList({
  audience = null,
  pageSize = 20,
  emptyMessage = 'No notifications yet.',
}) {
  const [filter, setFilter] = useState('active');
  const [page, setPage] = useState(1);
  const [items, setItems] = useState([]);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);

  const activeFilter = FILTERS.find((f) => f.id === filter) || FILTERS[0];

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    notificationService.clearNotificationCache();
    const result = await notificationService.listNotifications({
      status: activeFilter.status === 'active' ? undefined : activeFilter.status,
      category: activeFilter.category,
      audience,
      page,
      pageSize,
    });
    if (result.error) {
      setError(result.error.message || 'Could not load notifications');
      setItems([]);
    } else {
      setItems(result.data || []);
      setTotal(result.total || 0);
    }
    setLoading(false);
  }, [activeFilter, audience, page, pageSize]);

  useEffect(() => {
    load();
  }, [load]);

  const handleRead = async (id) => {
    try {
      await notificationService.markAsRead(id);
      setItems((prev) => prev.map((n) => (
        n.id === id ? { ...n, status: 'read', isUnread: false, readAt: new Date().toISOString() } : n
      )));
    } catch (err) {
      console.error(err);
    }
  };

  const handleArchive = async (id) => {
    try {
      await notificationService.archiveNotification(id);
      setItems((prev) => prev.filter((n) => n.id !== id));
    } catch (err) {
      console.error(err);
    }
  };

  const handleMarkAll = async () => {
    try {
      await notificationService.markAllRead(audience);
      await load();
    } catch (err) {
      console.error(err);
    }
  };

  const totalPages = Math.max(1, Math.ceil(total / pageSize));

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div
          className="flex flex-wrap gap-2"
          role="tablist"
          aria-label="Notification filters"
        >
          {FILTERS.map((f) => (
            <button
              key={f.id}
              type="button"
              role="tab"
              aria-selected={filter === f.id}
              className={`px-3 py-1.5 text-xs uppercase tracking-wider rounded-lg border transition-colors ${
                filter === f.id
                  ? 'border-brand-500 bg-brand-500/15 text-brand-400'
                  : 'border-brand-500/10 text-slate-400 hover:text-brand-400'
              }`}
              onClick={() => { setFilter(f.id); setPage(1); }}
            >
              {f.label}
            </button>
          ))}
        </div>
        <Button type="button" variant="ghost" className="text-xs" onClick={handleMarkAll}>
          Mark all read
        </Button>
      </div>

      {loading && (
        <div className="flex justify-center py-12"><Spinner /></div>
      )}

      {!loading && error && (
        <p className="text-sm text-red-400" role="alert">{error}</p>
      )}

      {!loading && !error && items.length === 0 && (
        <p className="text-sm text-slate-500 py-8 text-center">{emptyMessage}</p>
      )}

      {!loading && items.length > 0 && (
        <ul className="space-y-3" aria-live="polite">
          {items.map((n) => (
            <li key={n.id}>
              <NotificationItem
                notification={n}
                onRead={handleRead}
                onArchive={handleArchive}
              />
            </li>
          ))}
        </ul>
      )}

      {totalPages > 1 && (
        <div className="flex items-center justify-center gap-3 pt-2">
          <Button
            type="button"
            variant="ghost"
            disabled={page <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}
          >
            Previous
          </Button>
          <span className="text-xs text-slate-500">Page {page} of {totalPages}</span>
          <Button
            type="button"
            variant="ghost"
            disabled={page >= totalPages}
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
          >
            Next
          </Button>
        </div>
      )}
    </div>
  );
}
