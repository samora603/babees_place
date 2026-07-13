import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import SalesSummaryCard from './SalesSummaryCard';

const sampleSummary = {
  averageOrderValue: 750,
  totalRevenue: 1500,
  totalOrders: 4,
  completedOrders: 1,
  cancelledOrders: 1,
  pendingOrders: 1,
};

describe('SalesSummaryCard', () => {
  it('renders sales metrics', () => {
    render(<SalesSummaryCard summary={sampleSummary} loading={false} error={null} />);
    expect(screen.getByText('Average Order Value')).toBeInTheDocument();
    expect(screen.getByText('KES 750')).toBeInTheDocument();
    expect(screen.getByText('4')).toBeInTheDocument();
  });

  it('shows empty state when no orders', () => {
    render(
      <SalesSummaryCard
        summary={{ ...sampleSummary, totalOrders: 0 }}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText(/no orders recorded yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    render(<SalesSummaryCard summary={null} loading={false} error={new Error('Sales down')} onRetry={onRetry} />);
    expect(screen.getByText('Sales down')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });
});
