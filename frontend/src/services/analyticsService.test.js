import { describe, it, expect, vi, beforeEach } from 'vitest';
import { resetAnalyticsQueryCache } from './analyticsQueries';

const fromMock = vi.fn();

vi.mock('@/lib/supabaseClient', () => ({
  supabase: {
    from: (...args) => fromMock(...args),
  },
}));

function mockHeadCount(count) {
  return {
    select: () => ({
      then: (resolve) => resolve({ count, error: null, data: null }),
    }),
  };
}

function mockSelectData(data) {
  return {
    select: () => ({
      then: (resolve) => resolve({ data, error: null, count: null }),
    }),
  };
}

function mockQueryChain(result) {
  const chain = {
    select: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => chain),
    lt: vi.fn(() => chain),
    then: (resolve, reject) => Promise.resolve(result).then(resolve, reject),
  };
  return chain;
}

describe('analyticsService', () => {
  beforeEach(() => {
    fromMock.mockReset();
    resetAnalyticsQueryCache();
    vi.resetModules();
  });

  it('getDashboardSnapshot aggregates KPIs from Supabase', async () => {
    let ordersCalls = 0;
    fromMock.mockImplementation((table) => {
      if (table === 'profiles') return mockHeadCount(12);
      if (table === 'products') return mockHeadCount(25);
      if (table === 'orders') {
        ordersCalls += 1;
        if (ordersCalls === 1) return mockHeadCount(8);
        return mockSelectData([{ total: 500 }, { total: 300 }]);
      }
      return mockHeadCount(0);
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getDashboardSnapshot();

    expect(error).toBeNull();
    expect(data.kpis.totalUsers).toBe(12);
    expect(data.kpis.totalProducts).toBe(25);
    expect(data.kpis.totalOrders).toBe(8);
    expect(data.kpis.totalRevenue).toBe(800);
    expect(data.fetchedAt).toBeTruthy();
  });

  it('getDashboardSnapshot returns empty snapshot on error', async () => {
    fromMock.mockReturnValue({
      select: () => ({
        then: (resolve) => resolve({ count: null, error: { message: 'DB down' }, data: null }),
      }),
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getDashboardSnapshot();

    expect(error).toBeTruthy();
    expect(data.kpis.totalRevenue).toBe(0);
  });

  it('getRecentOrders maps latest orders', async () => {
    const orderRow = {
      id: 'abc12345-0000-0000-0000-000000000000',
      status: 'confirmed',
      total: 900,
      payment_status: 'paid',
      delivery_type: 'delivery',
      created_at: '2026-07-13T09:00:00.000Z',
      profiles: { full_name: 'Alex' },
    };
    fromMock.mockReturnValue(
      mockQueryChain({ data: [orderRow], error: null }),
    );

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getRecentOrders(10);

    expect(error).toBeNull();
    expect(data).toHaveLength(1);
    expect(data[0].orderNumber).toBe('#ABC12345');
    expect(data[0].customerName).toBe('Alex');
  });

  it('getRecentOrders returns empty array on error', async () => {
    fromMock.mockReturnValue(
      mockQueryChain({ data: null, error: { message: 'fail' } }),
    );

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getRecentOrders();

    expect(error).toBeTruthy();
    expect(data).toEqual([]);
  });

  it('getLowStockProducts maps products below threshold', async () => {
    fromMock.mockReturnValue(
      mockQueryChain({ data: [{ id: 'p1', name: 'Tea', stock: 1 }], error: null }),
    );

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getLowStockProducts();

    expect(error).toBeNull();
    expect(data[0].severity).toBe('critical');
    expect(data[0].threshold).toBe(5);
  });

  it('getDashboardActivity maps order_events', async () => {
    fromMock.mockReturnValue(
      mockQueryChain({
        data: [{
          id: 'e1',
          order_id: 'o1',
          event_type: 'order_placed',
          payload: {},
          created_at: '2026-07-13T09:00:00.000Z',
          orders: { id: 'o1', profiles: { full_name: 'Pat' } },
        }],
        error: null,
      }),
    );

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getDashboardActivity(15);

    expect(error).toBeNull();
    expect(data[0].description).toBe('Order Created');
    expect(data[0].userName).toBe('Pat');
  });

  it('getRevenueSummary aggregates recognized revenue', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'orders') {
        return mockQueryChain({
          data: [
            { total: 100, payment_status: 'paid', status: 'delivered', created_at: '2026-07-13T10:00:00.000Z' },
            { total: 50, payment_status: 'pending', status: 'pending', created_at: '2026-07-13T11:00:00.000Z' },
          ],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getRevenueSummary();

    expect(error).toBeNull();
    expect(data.allTime).toBe(100);
  });

  it('getSalesSummary returns order metrics', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'orders') {
        return mockQueryChain({
          data: [
            { total: 1000, payment_status: 'paid', status: 'delivered' },
            { total: 200, payment_status: 'pending', status: 'pending' },
          ],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getSalesSummary();

    expect(error).toBeNull();
    expect(data.totalOrders).toBe(2);
    expect(data.totalRevenue).toBe(1000);
  });

  it('getOrdersByStatus returns status buckets', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'orders') {
        return mockQueryChain({
          data: [{ status: 'pending' }, { status: 'delivered' }],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getOrdersByStatus();

    expect(error).toBeNull();
    expect(data.find((r) => r.key === 'pending')?.count).toBe(1);
    expect(data.find((r) => r.key === 'delivered')?.label).toBe('Completed');
  });

  it('getOrdersByFulfillment returns pickup and delivery counts', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'orders') {
        return mockQueryChain({
          data: [{ delivery_type: 'pickup' }, { delivery_type: 'delivery' }],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getOrdersByFulfillment();

    expect(error).toBeNull();
    expect(data.find((r) => r.key === 'pickup')?.count).toBe(1);
  });

  it('getOrdersByPaymentStatus returns payment buckets', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'orders') {
        return mockQueryChain({
          data: [{ payment_status: 'paid' }, { payment_status: 'refunded' }],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getOrdersByPaymentStatus();

    expect(error).toBeNull();
    expect(data.find((r) => r.key === 'paid')?.count).toBe(1);
    expect(data.find((r) => r.key === 'refunded')?.count).toBe(1);
  });

  it('getTopSellingProducts aggregates line items', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'order_items') {
        return mockQueryChain({
          data: [{
            product_id: 'p1',
            name: 'Honey',
            price: 100,
            quantity: 2,
            orders: { status: 'delivered', payment_status: 'paid' },
            products: { category: 'Food' },
          }],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getTopSellingProducts(5);

    expect(error).toBeNull();
    expect(data[0].productName).toBe('Honey');
    expect(data[0].revenueGenerated).toBe(200);
  });

  it('getTopCategories aggregates by category', async () => {
    fromMock.mockImplementation((table) => {
      if (table === 'order_items') {
        return mockQueryChain({
          data: [{
            price: 50,
            quantity: 3,
            orders: { status: 'delivered', payment_status: 'paid' },
            products: { category: 'Tea', categories: { name: 'Tea' } },
          }],
          error: null,
        });
      }
      return mockQueryChain({ data: [], error: null });
    });

    const { analyticsService } = await import('./analyticsService');
    const { data, error } = await analyticsService.getTopCategories(5);

    expect(error).toBeNull();
    expect(data[0].categoryName).toBe('Tea');
    expect(data[0].revenue).toBe(150);
  });
});
