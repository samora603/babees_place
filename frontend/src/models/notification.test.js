import { describe, it, expect } from 'vitest';
import {
  mapNotification,
  mapNotificationPreferences,
  mapNotificationPreferencesToDb,
  isPaymentEvent,
  isOrderEvent,
  NOTIFICATION_EVENTS,
  ORDER_STATUS_EVENT_MAP,
} from '@/models/notification';

describe('notification model', () => {
  it('maps notification rows', () => {
    const mapped = mapNotification({
      id: 'n1',
      user_id: 'u1',
      event_type: 'order_created',
      channel: 'in_app',
      title: 'Order placed',
      body: 'Thanks',
      status: 'unread',
      audience: 'customer',
      metadata: { orderId: 'o1' },
      created_at: '2026-01-01',
      updated_at: '2026-01-01',
    });
    expect(mapped.isUnread).toBe(true);
    expect(mapped.userId).toBe('u1');
    expect(mapped.eventType).toBe('order_created');
  });

  it('maps preferences to/from db', () => {
    const mapped = mapNotificationPreferences({
      user_id: 'u1',
      email_enabled: true,
      sms_enabled: false,
      in_app_enabled: true,
      push_enabled: false,
      marketing_emails: true,
      order_updates: true,
      payment_updates: false,
    });
    expect(mapped.paymentUpdates).toBe(false);
    expect(mapNotificationPreferencesToDb('u1', mapped).payment_updates).toBe(false);
  });

  it('classifies events', () => {
    expect(isPaymentEvent(NOTIFICATION_EVENTS.PAYMENT_FAILED)).toBe(true);
    expect(isOrderEvent(NOTIFICATION_EVENTS.DELIVERED)).toBe(true);
    expect(ORDER_STATUS_EVENT_MAP.confirmed).toBe(NOTIFICATION_EVENTS.ORDER_CONFIRMED);
  });
});
