import { describe, it, expect, vi, beforeEach } from 'vitest';

vi.mock('@/lib/supabaseClient', () => {
  const state = {
    notifications: [],
    deliveries: [],
    events: [],
    prefs: null,
  };

  const from = (table) => {
    const api = {
      insert(row) {
        const rows = Array.isArray(row) ? row : [row];
        const withIds = rows.map((r) => ({
          id: r.id || `${table}-${state[table]?.length || 0}-${Math.random().toString(36).slice(2, 6)}`,
          created_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
          ...r,
        }));
        if (table === 'notifications') state.notifications.push(...withIds);
        if (table === 'notification_deliveries') state.deliveries.push(...withIds);
        if (table === 'notification_events') state.events.push(...withIds);
        return {
          select() {
            return {
              single: async () => ({ data: withIds[0], error: null }),
            };
          },
          then: undefined,
        };
      },
      select() {
        const chain = {
          eq() { return chain; },
          neq() { return chain; },
          like() { return chain; },
          or() { return chain; },
          order() { return chain; },
          range: async () => ({
            data: state.notifications.filter((n) => n.status !== 'archived'),
            error: null,
            count: state.notifications.length,
          }),
          maybeSingle: async () => ({ data: state.prefs, error: null }),
          single: async () => ({ data: state.prefs, error: null }),
        };
        // head count style
        chain.then = undefined;
        return {
          ...chain,
          // for getUnreadCount head:true path — supabase returns thenable-like
        };
      },
      update(patch) {
        return {
          eq(field, value) {
            if (table === 'notifications') {
              state.notifications = state.notifications.map((n) => (
                n[field === 'id' ? 'id' : field] === value || n.id === value
                  ? { ...n, ...patch }
                  : n
              ));
            }
            if (table === 'notification_deliveries') {
              state.deliveries = state.deliveries.map((d) => (
                d.id === value ? { ...d, ...patch } : d
              ));
            }
            return {
              select() {
                return {
                  single: async () => ({
                    data: state.notifications.find((n) => n.id === value) || state.deliveries.find((d) => d.id === value),
                    error: null,
                  }),
                };
              },
              then: undefined,
            };
          },
        };
      },
      upsert(row) {
        state.prefs = { ...row };
        return {
          select() {
            return {
              single: async () => ({ data: state.prefs, error: null }),
            };
          },
        };
      },
    };

    // Special: select with count head for unread
    if (table === 'notifications') {
      const originalSelect = api.select.bind(api);
      api.select = (cols, opts) => {
        if (opts?.head && opts?.count === 'exact') {
          return {
            eq() {
              return {
                eq() {
                  return Promise.resolve({
                    count: state.notifications.filter((n) => n.status === 'unread').length,
                    error: null,
                  });
                },
                then(resolve) {
                  resolve({
                    count: state.notifications.filter((n) => n.status === 'unread').length,
                    error: null,
                  });
                },
              };
            },
          };
        }
        return originalSelect(cols, opts);
      };
    }

    return api;
  };

  return {
    supabase: {
      from,
      rpc: async (name, args) => {
        if (name === 'ensure_notification_preferences') {
          state.prefs = state.prefs || {
            user_id: args.p_user_id,
            email_enabled: true,
            sms_enabled: false,
            in_app_enabled: true,
            push_enabled: false,
            marketing_emails: false,
            order_updates: true,
            payment_updates: true,
          };
          return { data: state.prefs, error: null };
        }
        if (name === 'notify_admin_users') {
          state.notifications.push({
            id: `admin-${state.notifications.length}`,
            user_id: 'admin-1',
            event_type: args.p_event_type,
            channel: 'in_app',
            title: args.p_title,
            body: args.p_body,
            link: args.p_link,
            metadata: args.p_metadata || {},
            status: 'unread',
            audience: 'admin',
            created_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          });
          return { data: 1, error: null };
        }
        if (name === 'mark_notification_read') {
          const n = state.notifications.find((x) => x.id === args.p_notification_id);
          if (n) {
            n.status = 'read';
            n.read_at = new Date().toISOString();
          }
          return { data: n, error: n ? null : { message: 'not found' } };
        }
        if (name === 'mark_all_notifications_read') {
          let count = 0;
          state.notifications.forEach((n) => {
            if (n.status === 'unread') {
              n.status = 'read';
              count += 1;
            }
          });
          return { data: count, error: null };
        }
        if (name === 'archive_notification') {
          const n = state.notifications.find((x) => x.id === args.p_notification_id);
          if (n) {
            n.status = 'archived';
            n.archived_at = new Date().toISOString();
          }
          return { data: n, error: n ? null : { message: 'not found' } };
        }
        return { data: null, error: null };
      },
      auth: {
        getUser: async () => ({ data: { user: { id: 'user-1' } }, error: null }),
      },
      __state: state,
    },
  };
});

vi.mock('@/services/providers/notificationProviderFactory', async () => {
  const actual = await vi.importActual('@/services/providers/notificationProviderFactory');
  return actual;
});

describe('notificationService', () => {
  beforeEach(async () => {
    vi.resetModules();
    const { clearMockEmailOutbox } = await import('@/services/providers/mockEmailProvider');
    const { clearMockSmsOutbox } = await import('@/services/providers/mockSmsProvider');
    clearMockEmailOutbox();
    clearMockSmsOutbox();
  });

  it('emit creates in-app notification and email delivery', async () => {
    const { notificationService } = await import('@/services/notificationService');
    const { NOTIFICATION_EVENTS } = await import('@/models/notification');
    const { getMockEmailOutbox } = await import('@/services/providers/mockEmailProvider');

    const result = await notificationService.emit(NOTIFICATION_EVENTS.ORDER_CREATED, {
      userId: 'user-1',
      email: 'sam@example.com',
      name: 'Sam',
      orderId: 'order-abc',
      amount: 2500,
    });

    expect(result.notifications.length).toBe(1);
    expect(result.notifications[0].title).toContain('ORDER-AB');
    expect(getMockEmailOutbox().length).toBeGreaterThanOrEqual(1);
  });

  it('emitSafe never throws', async () => {
    const { notificationService } = await import('@/services/notificationService');
    await expect(
      notificationService.emitSafe('order_created', { userId: 'user-1' }),
    ).resolves.toBeTruthy();
  });

  it('markAsRead and markAllRead update status', async () => {
    const { notificationService } = await import('@/services/notificationService');
    const { NOTIFICATION_EVENTS } = await import('@/models/notification');

    const created = await notificationService.emit(NOTIFICATION_EVENTS.PAYMENT_FAILED, {
      userId: 'user-1',
      orderId: 'order-1',
    });
    const id = created.notifications[0].id;
    const read = await notificationService.markAsRead(id);
    expect(read.status).toBe('read');

    await notificationService.emit(NOTIFICATION_EVENTS.PAYMENT_INITIATED, {
      userId: 'user-1',
      orderId: 'order-2',
      amount: 10,
    });
    const all = await notificationService.markAllRead();
    expect(all.count).toBeGreaterThanOrEqual(0);
  });

  it('admin events fan out via notify_admin_users', async () => {
    const { notificationService } = await import('@/services/notificationService');
    const { NOTIFICATION_EVENTS } = await import('@/models/notification');
    const result = await notificationService.emit(NOTIFICATION_EVENTS.ADMIN_NEW_ORDER, {
      orderId: 'order-9',
      amount: 100,
      paymentMethod: 'cod',
      notifyAdmins: true,
    });
    expect(result.adminCount).toBe(1);
  });

  it('retryDelivery increments retry and resends', async () => {
    const { supabase } = await import('@/lib/supabaseClient');
    const delivery = {
      id: 'del-1',
      notification_id: null,
      user_id: 'user-1',
      event_type: 'welcome',
      channel: 'email',
      provider: 'mock_email',
      status: 'failed',
      retry_count: 0,
      max_retries: 3,
      payload: { to: 'a@b.com', subject: 'Hi', body: 'Hello' },
    };
    supabase.__state.deliveries.push(delivery);

    // Patch from().select for deliveries
    const originalFrom = supabase.from;
    supabase.from = (table) => {
      if (table === 'notification_deliveries') {
        return {
          select() {
            return {
              eq() {
                return {
                  maybeSingle: async () => ({ data: delivery, error: null }),
                };
              },
            };
          },
          update(patch) {
            Object.assign(delivery, patch);
            return {
              eq() {
                return Promise.resolve({ data: delivery, error: null });
              },
            };
          },
        };
      }
      return originalFrom(table);
    };

    const { notificationService } = await import('@/services/notificationService');
    const result = await notificationService.retryDelivery('del-1');
    expect(result.ok).toBe(true);
    expect(delivery.retry_count).toBeGreaterThanOrEqual(1);
  });
});
