import { Link } from 'react-router-dom';
import NotificationStatusBadge from './NotificationStatusBadge';

function formatWhen(iso) {
  if (!iso) return '';
  try {
    return new Intl.DateTimeFormat(undefined, {
      dateStyle: 'medium',
      timeStyle: 'short',
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export default function NotificationItem({
  notification,
  onRead,
  onArchive,
  showActions = true,
}) {
  const isUnread = notification.status === 'unread';

  return (
    <article
      className={`rounded-xl border p-4 transition-colors ${
        isUnread
          ? 'border-brand-500/30 bg-brand-500/5'
          : 'border-brand-500/10 bg-surface-card/40'
      }`}
      aria-labelledby={`notif-title-${notification.id}`}
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2 mb-1">
            <h3
              id={`notif-title-${notification.id}`}
              className={`text-sm font-semibold ${isUnread ? 'text-white' : 'text-slate-300'}`}
            >
              {notification.title}
            </h3>
            <NotificationStatusBadge status={notification.status} />
          </div>
          <p className="text-sm text-slate-400 whitespace-pre-wrap">{notification.body}</p>
          <p className="text-xs text-slate-500 mt-2">{formatWhen(notification.createdAt)}</p>
          {notification.link && (
            <Link
              to={notification.link}
              className="inline-block mt-2 text-xs text-brand-400 hover:underline"
              onClick={() => { if (isUnread && onRead) onRead(notification.id); }}
            >
              View details
            </Link>
          )}
        </div>
        {showActions && (
          <div className="flex flex-col gap-1 shrink-0">
            {isUnread && (
              <button
                type="button"
                className="text-xs text-slate-400 hover:text-brand-400 px-2 py-1"
                onClick={() => onRead?.(notification.id)}
              >
                Mark read
              </button>
            )}
            {notification.status !== 'archived' && (
              <button
                type="button"
                className="text-xs text-slate-500 hover:text-slate-300 px-2 py-1"
                onClick={() => onArchive?.(notification.id)}
              >
                Archive
              </button>
            )}
          </div>
        )}
      </div>
    </article>
  );
}
