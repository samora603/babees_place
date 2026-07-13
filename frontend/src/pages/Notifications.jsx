import { lazy, Suspense } from 'react';
import Spinner from '@/components/ui/Spinner';

const NotificationList = lazy(() => import('@/components/notifications/NotificationList'));

export default function Notifications() {
  return (
    <div className="section-container py-10 max-w-3xl">
      <header className="mb-8">
        <h1 className="font-display text-3xl text-white tracking-wide">Notifications</h1>
        <p className="text-slate-400 mt-2 text-sm">
          Order updates, payment alerts, and account messages.
        </p>
      </header>
      <Suspense fallback={<div className="flex justify-center py-16"><Spinner size="lg" /></div>}>
        <NotificationList audience="customer" />
      </Suspense>
    </div>
  );
}
