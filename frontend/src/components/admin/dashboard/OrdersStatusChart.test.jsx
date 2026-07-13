import { describe, it, expect, vi } from 'vitest';
import { createElement } from 'react';
import { render, screen } from '@testing-library/react';

vi.mock('recharts', () => {
  const Pass = ({ children }) => createElement('div', { 'data-testid': 'recharts-mock' }, children);
  return {
    ResponsiveContainer: Pass,
    BarChart: Pass,
    Bar: () => null,
    XAxis: () => null,
    YAxis: () => null,
    CartesianGrid: () => null,
    Tooltip: () => null,
    Cell: () => null,
  };
});

import OrdersStatusChart from './OrdersStatusChart';

describe('OrdersStatusChart', () => {
  it('renders chart with accessible table', () => {
    render(
      <OrdersStatusChart
        statusCounts={[
          { key: 'pending', label: 'Pending', count: 2 },
          { key: 'delivered', label: 'Completed', count: 1 },
        ]}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByRole('img', { name: /order counts by status/i })).toBeInTheDocument();
    expect(screen.getByText('Pending')).toBeInTheDocument();
    expect(screen.getByText('Completed')).toBeInTheDocument();
  });

  it('shows empty state when counts are zero', () => {
    render(
      <OrdersStatusChart
        statusCounts={[{ key: 'pending', label: 'Pending', count: 0 }]}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText(/no orders to chart/i)).toBeInTheDocument();
  });
});
