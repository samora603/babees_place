import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import RevenueSummaryCard from './RevenueSummaryCard';

describe('RevenueSummaryCard', () => {
  it('renders revenue period values formatted as currency', () => {
    render(
      <RevenueSummaryCard
        summary={{ today: 500, thisWeek: 1200, thisMonth: 3000, allTime: 10000 }}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText('Today')).toBeInTheDocument();
    expect(screen.getByText('KES 500')).toBeInTheDocument();
    expect(screen.getByText('KES 10,000')).toBeInTheDocument();
  });

  it('shows empty state when all values are zero', () => {
    render(
      <RevenueSummaryCard
        summary={{ today: 0, thisWeek: 0, thisMonth: 0, allTime: 0 }}
        loading={false}
        error={null}
      />,
    );
    expect(screen.getByText(/no recognized revenue yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    render(
      <RevenueSummaryCard summary={null} loading={false} error={new Error('Revenue failed')} onRetry={onRetry} />,
    );
    expect(screen.getByText('Revenue failed')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });

  it('shows skeleton while loading', () => {
    render(<RevenueSummaryCard summary={null} loading error={null} />);
    expect(screen.getByLabelText('Loading widget')).toBeInTheDocument();
  });
});
