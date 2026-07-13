import { describe, it, expect } from 'vitest';
import {
  revenueSummaryToChartData,
  statusCountsToChartData,
  isChartDataEmpty,
  topProductsToDisplayRows,
  topCategoriesToDisplayRows,
} from '@/models/chartPresentation';

describe('chartPresentation', () => {
  it('revenueSummaryToChartData maps periods for charts', () => {
    const data = revenueSummaryToChartData({ today: 100, thisWeek: 200, thisMonth: 300, allTime: 500 });
    expect(data).toHaveLength(4);
    expect(data[0]).toEqual({ key: 'today', label: 'Today', value: 100 });
  });

  it('statusCountsToChartData maps count to value', () => {
    const data = statusCountsToChartData([{ key: 'pending', label: 'Pending', count: 3 }]);
    expect(data[0].value).toBe(3);
  });

  it('isChartDataEmpty detects zero series', () => {
    expect(isChartDataEmpty([{ key: 'a', label: 'A', value: 0 }])).toBe(true);
    expect(isChartDataEmpty([{ key: 'a', label: 'A', value: 2 }])).toBe(false);
  });

  it('topProductsToDisplayRows adds relative bar percent', () => {
    const rows = topProductsToDisplayRows([
      { productId: '1', productName: 'A', unitsSold: 2, revenueGenerated: 200 },
      { productId: '2', productName: 'B', unitsSold: 1, revenueGenerated: 100 },
    ]);
    expect(rows[0].revenueBarPercent).toBe(100);
    expect(rows[1].revenueBarPercent).toBe(50);
  });

  it('topCategoriesToDisplayRows adds revenue percentage', () => {
    const rows = topCategoriesToDisplayRows([
      { categoryName: 'Tea', unitsSold: 3, revenue: 300 },
      { categoryName: 'Honey', unitsSold: 1, revenue: 100 },
    ]);
    expect(rows[0].revenuePercent).toBe(75);
    expect(rows[1].revenuePercent).toBe(25);
  });
});
