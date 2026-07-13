import { Link } from 'react-router-dom';
import { FiBell } from 'react-icons/fi';
import { useNotifications } from '@/hooks/useNotifications';

/**
 * Navbar notification bell with unread badge.
 */
export default function NotificationBell({ to = '/notifications', audience = null, label = 'Notifications' }) {
  const { unreadCount } = useNotifications({ audience });

  return (
    <Link
      to={to}
      className="btn-ghost relative hover:text-brand-400 group"
      aria-label={unreadCount > 0 ? `${label}, ${unreadCount} unread` : label}
    >
      <FiBell size={20} className="group-hover:scale-110 transition-transform" aria-hidden="true" />
      {unreadCount > 0 && (
        <span
          className="absolute -top-1.5 -right-1.5 bg-brand-500 text-black text-[10px] rounded-full min-w-4 h-4 px-0.5 flex items-center justify-center font-bold shadow-[0_0_10px_rgba(212,175,55,0.5)]"
          aria-hidden="true"
        >
          {unreadCount > 9 ? '9+' : unreadCount}
        </span>
      )}
    </Link>
  );
}
