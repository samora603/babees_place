import { describe, it, expect, vi } from 'vitest';
import { createElement } from 'react';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';

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
    PieChart: Pass,
    Pie: () => null,
    Legend: () => null,
  };
});

import RevenueTrendChart from './RevenueTrendChart';

describe('RevenueTrendChart', () => {
  it('renders chart when revenue data exists', () => {
    render(
      <RevenueTrendChart
        summary={{ today: 500, thisWeek: 1200, thisMonth: 3000, allTime: 10000 }}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByRole('img', { name: /revenue by period/i })).toBeInTheDocument();
    expect(screen.getByText('Today')).toBeInTheDocument();
  });

  it('shows empty state when all values are zero', () => {
    render(
      <RevenueTrendChart
        summary={{ today: 0, thisWeek: 0, thisMonth: 0, allTime: 0 }}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText(/no recognized revenue to chart/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    render(
      <RevenueTrendChart summary={null} loading={false} error={new Error('Chart failed')} onRetry={onRetry} />,
    );
    expect(screen.getByText('Chart failed')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });

  it('shows skeleton while loading', () => {
    render(<RevenueTrendChart summary={null} loading error={null} />);
    expect(screen.getByLabelText('Loading widget')).toBeInTheDocument();
  });
});
