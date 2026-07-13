import { describe, it, expect } from 'vitest';
import {
  isRecognizedRevenueOrder,
  buildRevenueSummary,
  buildSalesSummary,
  buildOrdersByStatus,
  buildOrdersByFulfillment,
  buildOrdersByPaymentStatus,
  aggregateTopProducts,
  aggregateTopCategories,
  startOfCalendarDay,
  revenueSummaryToDisplayItems,
} from '@/models/analytics';

const NOW = new Date('2026-07-13T14:00:00.000Z');

describe('analytics models', () => {
  describe('isRecognizedRevenueOrder', () => {
    it('includes paid non-cancelled orders', () => {
      expect(isRecognizedRevenueOrder({ status: 'delivered', payment_status: 'paid' })).toBe(true);
    });

    it('excludes cancelled and unpaid orders', () => {
      expect(isRecognizedRevenueOrder({ status: 'cancelled', payment_status: 'paid' })).toBe(false);
      expect(isRecognizedRevenueOrder({ status: 'pending', payment_status: 'pending' })).toBe(false);
    });
  });

  describe('buildRevenueSummary', () => {
    const orders = [
      { total: 100, payment_status: 'paid', status: 'delivered', created_at: '2026-07-13T10:00:00.000Z' },
      { total: 200, payment_status: 'paid', status: 'confirmed', created_at: '2026-07-12T10:00:00.000Z' },
      { total: 500, payment_status: 'paid', status: 'delivered', created_at: '2026-06-01T10:00:00.000Z' },
      { total: 999, payment_status: 'pending', status: 'pending', created_at: '2026-07-13T11:00:00.000Z' },
    ];

    it('sums recognized revenue by period', () => {
      const summary = buildRevenueSummary(orders, NOW);
      expect(summary.allTime).toBe(800);
      expect(summary.today).toBe(100);
      expect(summary.thisMonth).toBe(300);
    });
  });

  describe('buildSalesSummary', () => {
    it('computes AOV and order buckets', () => {
      const orders = [
        { total: 1000, payment_status: 'paid', status: 'delivered' },
        { total: 500, payment_status: 'paid', status: 'confirmed' },
        { total: 200, payment_status: 'pending', status: 'pending' },
        { total: 0, payment_status: 'pending', status: 'cancelled' },
      ];
      const summary = buildSalesSummary(orders);
      expect(summary.totalOrders).toBe(4);
      expect(summary.totalRevenue).toBe(1500);
      expect(summary.averageOrderValue).toBe(750);
      expect(summary.completedOrders).toBe(1);
      expect(summary.cancelledOrders).toBe(1);
      expect(summary.pendingOrders).toBe(1);
    });
  });

  describe('buildOrdersByStatus', () => {
    it('returns chart-ready counts for all buckets', () => {
      const rows = buildOrdersByStatus([
        { status: 'pending' },
        { status: 'pending' },
        { status: 'shipped' },
        { status: 'delivered' },
      ]);
      expect(rows.find((r) => r.key === 'pending')?.count).toBe(2);
      expect(rows.find((r) => r.key === 'shipped')?.label).toBe('Out for Delivery');
      expect(rows.find((r) => r.key === 'delivered')?.label).toBe('Completed');
    });
  });

  describe('buildOrdersByFulfillment', () => {
    it('counts pickup and delivery', () => {
      const rows = buildOrdersByFulfillment([
        { delivery_type: 'pickup' },
        { delivery_type: 'delivery' },
        { delivery_type: 'delivery' },
      ]);
      expect(rows.find((r) => r.key === 'pickup')?.count).toBe(1);
      expect(rows.find((r) => r.key === 'delivery')?.count).toBe(2);
    });
  });

  describe('buildOrdersByPaymentStatus', () => {
    it('counts payment statuses including future-safe buckets', () => {
      const rows = buildOrdersByPaymentStatus([
        { payment_status: 'paid' },
        { payment_status: 'refunded' },
        { payment_status: 'failed' },
        {},
      ]);
      expect(rows.find((r) => r.key === 'paid')?.count).toBe(1);
      expect(rows.find((r) => r.key === 'refunded')?.count).toBe(1);
      expect(rows.find((r) => r.key === 'failed')?.count).toBe(1);
      expect(rows.find((r) => r.key === 'pending')?.count).toBe(1);
    });
  });

  describe('aggregateTopProducts', () => {
    it('aggregates units and revenue from recognized orders only', () => {
      const items = [
        { product_id: 'p1', name: 'Honey', price: 100, quantity: 2, orders: { status: 'delivered', payment_status: 'paid' } },
        { product_id: 'p1', name: 'Honey', price: 100, quantity: 1, orders: { status: 'delivered', payment_status: 'paid' } },
        { product_id: 'p2', name: 'Wax', price: 50, quantity: 4, orders: { status: 'cancelled', payment_status: 'paid' } },
      ];
      const top = aggregateTopProducts(items, 10);
      expect(top).toHaveLength(1);
      expect(top[0].productName).toBe('Honey');
      expect(top[0].unitsSold).toBe(3);
      expect(top[0].revenueGenerated).toBe(300);
    });
  });

  describe('aggregateTopCategories', () => {
    it('rolls up category revenue from order items', () => {
      const items = [
        {
          price: 100,
          quantity: 1,
          orders: { status: 'delivered', payment_status: 'paid' },
          products: { category: 'Spreads', categories: { name: 'Spreads' } },
        },
        {
          price: 200,
          quantity: 2,
          orders: { status: 'delivered', payment_status: 'paid' },
          products: { category: null, categories: { name: 'Wellness' } },
        },
      ];
      const top = aggregateTopCategories(items, 10);
      expect(top[0].categoryName).toBe('Wellness');
      expect(top[0].revenue).toBe(400);
    });
  });

  it('startOfCalendarDay zeroes time component', () => {
    const start = startOfCalendarDay(NOW);
    expect(start.getHours()).toBe(0);
    expect(start.getMinutes()).toBe(0);
  });

  it('revenueSummaryToDisplayItems returns four periods', () => {
    const items = revenueSummaryToDisplayItems({ today: 1, thisWeek: 2, thisMonth: 3, allTime: 4 });
    expect(items).toHaveLength(4);
    expect(items[0].key).toBe('today');
  });
});
