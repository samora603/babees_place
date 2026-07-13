import { useCallback, useEffect, useState } from 'react';
import { notificationService } from '@/services/notificationService';
import { useAuth } from '@/context/AuthContext';

/**
 * Shared unread badge + list helpers for navbar / admin header.
 */
export function useNotifications(opts = {}) {
  const { user } = useAuth();
  const audience = opts.audience || null;
  const pollMs = opts.pollMs ?? 30_000;
  const [unreadCount, setUnreadCount] = useState(0);
  const [loading, setLoading] = useState(false);

  const refreshUnread = useCallback(async () => {
    if (!user) {
      setUnreadCount(0);
      return 0;
    }
    try {
      const count = await notificationService.getUnreadCount({ audience });
      setUnreadCount(count);
      return count;
    } catch {
      return unreadCount;
    }
  }, [user, audience, unreadCount]);

  useEffect(() => {
    if (!user) {
      setUnreadCount(0);
      return undefined;
    }
    let mounted = true;
    (async () => {
      setLoading(true);
      const count = await notificationService.getUnreadCount({ audience }).catch(() => 0);
      if (mounted) {
        setUnreadCount(count);
        setLoading(false);
      }
    })();

    const timer = setInterval(() => {
      notificationService.getUnreadCount({ audience })
        .then((c) => { if (mounted) setUnreadCount(c); })
        .catch(() => {});
    }, pollMs);

    return () => {
      mounted = false;
      clearInterval(timer);
    };
  }, [user, audience, pollMs]);

  return { unreadCount, loading, refreshUnread, setUnreadCount };
}
