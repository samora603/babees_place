import { describe, it, expect } from 'vitest';
import {
  buildDashboardSnapshot,
  createEmptyDashboardSnapshot,
  kpisToCardValues,
  isDashboardEmpty,
  EMPTY_DASHBOARD_KPIS,
  formatOrderNumber,
  getLowStockSeverity,
  describeOrderEvent,
  formatRelativeTime,
  mapRecentOrderRow,
  mapLowStockProductRow,
  mapActivityEventRow,
} from '@/models/dashboard';

describe('dashboard models', () => {
  it('createEmptyDashboardSnapshot returns zeroed KPIs', () => {
    const snapshot = createEmptyDashboardSnapshot();
    expect(snapshot.kpis).toEqual(EMPTY_DASHBOARD_KPIS);
    expect(snapshot.fetchedAt).toBeTruthy();
  });

  it('buildDashboardSnapshot coerces numeric fields', () => {
    const snapshot = buildDashboardSnapshot({
      totalRevenue: '1500',
      totalOrders: 3,
      totalProducts: 10,
      totalUsers: 2,
    });
    expect(snapshot.kpis.totalRevenue).toBe(1500);
    expect(snapshot.kpis.totalOrders).toBe(3);
  });

  it('kpisToCardValues returns four KPI descriptors', () => {
    const cards = kpisToCardValues({
      totalRevenue: 1000,
      totalOrders: 5,
      totalProducts: 8,
      totalUsers: 4,
    });
    expect(cards).toHaveLength(4);
    expect(cards[0].key).toBe('totalRevenue');
    expect(cards[0].format).toBe('currency');
  });

  it('isDashboardEmpty is true when all KPIs are zero', () => {
    expect(isDashboardEmpty(EMPTY_DASHBOARD_KPIS)).toBe(true);
    expect(isDashboardEmpty({ ...EMPTY_DASHBOARD_KPIS, totalOrders: 1 })).toBe(false);
  });

  it('formatOrderNumber builds short uppercase reference', () => {
    expect(formatOrderNumber('abcdef12-3456-7890-abcd-ef1234567890')).toBe('#ABCDEF12');
  });

  it('getLowStockSeverity classifies stock levels', () => {
    expect(getLowStockSeverity(0)).toBe('out');
    expect(getLowStockSeverity(-1)).toBe('out');
    expect(getLowStockSeverity(1)).toBe('critical');
    expect(getLowStockSeverity(2)).toBe('critical');
    expect(getLowStockSeverity(3)).toBe('warning');
    expect(getLowStockSeverity(4)).toBe('warning');
  });

  it('describeOrderEvent maps event types to labels', () => {
    expect(describeOrderEvent({ event_type: 'order_placed' })).toBe('Order Created');
    expect(describeOrderEvent({ event_type: 'order_cancelled' })).toBe('Cancelled');
    expect(describeOrderEvent({ event_type: 'payment_status_changed', payload: { to: 'paid' } })).toBe('Payment Confirmed');
    expect(describeOrderEvent({ event_type: 'status_changed', payload: { to: 'ready_for_pickup' } })).toBe('Ready for Pickup');
    expect(describeOrderEvent({ event_type: 'status_changed', payload: { to: 'delivered' } })).toBe('Delivered');
  });

  it('formatRelativeTime returns human-readable deltas', () => {
    const now = Date.parse('2026-07-13T10:00:00.000Z');
    expect(formatRelativeTime('2026-07-13T09:59:30.000Z', now)).toBe('just now');
    expect(formatRelativeTime('2026-07-13T09:30:00.000Z', now)).toBe('30m ago');
    expect(formatRelativeTime('2026-07-13T08:00:00.000Z', now)).toBe('2h ago');
  });

  it('mapRecentOrderRow maps Supabase order embed', () => {
    const row = mapRecentOrderRow({
      id: 'abc12345-0000-0000-0000-000000000000',
      status: 'pending',
      total: 1500,
      payment_status: 'pending',
      delivery_type: 'pickup',
      created_at: '2026-07-13T09:00:00.000Z',
      profiles: { full_name: 'Jane Doe' },
    });
    expect(row.orderNumber).toBe('#ABC12345');
    expect(row.customerName).toBe('Jane Doe');
    expect(row.total).toBe(1500);
  });

  it('mapLowStockProductRow includes severity and threshold', () => {
    const row = mapLowStockProductRow({ id: 'prod-uuid-1234', name: 'Honey', stock: 2 });
    expect(row.severity).toBe('critical');
    expect(row.threshold).toBe(5);
    expect(row.sku).toBe('PROD-UUI');
  });

  it('mapActivityEventRow maps order_events with customer name', () => {
    const row = mapActivityEventRow({
      id: 'evt-1',
      order_id: 'order-uuid-99',
      event_type: 'order_placed',
      payload: {},
      created_at: '2026-07-13T09:00:00.000Z',
      orders: { id: 'order-uuid-99', profiles: { full_name: 'Sam' } },
    });
    expect(row.description).toBe('Order Created');
    expect(row.userName).toBe('Sam');
    expect(row.iconKey).toBe('placed');
  });
});
