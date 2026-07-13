import { lazy, Suspense } from 'react';
import Spinner from '@/components/ui/Spinner';
import { useNotifications } from '@/hooks/useNotifications';

const NotificationList = lazy(() => import('@/components/notifications/NotificationList'));

export default function AdminNotifications() {
  const { unreadCount } = useNotifications({ audience: 'admin' });

  return (
    <div className="p-8 max-w-4xl">
      <header className="mb-8">
        <h1 className="font-display text-2xl text-white tracking-widest uppercase">
          Alerts
        </h1>
        <p className="text-slate-400 mt-2 text-sm">
          New orders, payments, and inventory warnings
          {unreadCount > 0 ? ` · ${unreadCount} unread` : ''}.
        </p>
      </header>
      <Suspense fallback={<div className="flex justify-center py-16"><Spinner size="lg" /></div>}>
        <NotificationList
          audience="admin"
          emptyMessage="No admin alerts yet."
        />
      </Suspense>
    </div>
  );
}
