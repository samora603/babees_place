import { describe, it, expect, vi } from 'vitest';
import { createElement } from 'react';
import { render, screen } from '@testing-library/react';

vi.mock('recharts', () => {
  const Pass = ({ children }) => createElement('div', { 'data-testid': 'recharts-mock' }, children);
  return {
    ResponsiveContainer: Pass,
    PieChart: Pass,
    Pie: () => null,
    Tooltip: () => null,
    Cell: () => null,
    Legend: () => null,
  };
});

import FulfillmentChart from './FulfillmentChart';
import PaymentStatusChart from './PaymentStatusChart';

describe('FulfillmentChart', () => {
  it('renders donut chart container', () => {
    render(
      <FulfillmentChart
        fulfillmentCounts={[
          { key: 'pickup', label: 'Pickup', count: 4 },
          { key: 'delivery', label: 'Delivery', count: 2 },
        ]}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByRole('img', { name: /pickup versus delivery/i })).toBeInTheDocument();
    expect(screen.getAllByTestId('recharts-mock').length).toBeGreaterThan(0);
  });
});

describe('PaymentStatusChart', () => {
  it('renders pie chart and empty state', () => {
    const { rerender } = render(
      <PaymentStatusChart
        paymentCounts={[{ key: 'paid', label: 'Paid', count: 3 }]}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByRole('img', { name: /payment status/i })).toBeInTheDocument();

    rerender(
      <PaymentStatusChart
        paymentCounts={[{ key: 'paid', label: 'Paid', count: 0 }]}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText(/no payment status data/i)).toBeInTheDocument();
  });
});
