import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import TopProductsWidget from './TopProductsWidget';

const products = [{
  productId: 'p1',
  productName: 'Raw Honey',
  unitsSold: 12,
  revenueGenerated: 3600,
}];

describe('TopProductsWidget', () => {
  it('renders product rows with revenue share bar', () => {
    render(<TopProductsWidget products={products} loading={false} error={null} />);
    expect(screen.getByText('Raw Honey')).toBeInTheDocument();
    expect(screen.getByText('12')).toBeInTheDocument();
    expect(screen.getByText('KES 3,600')).toBeInTheDocument();
    expect(screen.getByRole('progressbar', { name: /raw honey revenue share/i })).toBeInTheDocument();
  });

  it('shows empty state', () => {
    render(<TopProductsWidget products={[]} loading={false} error={null} />);
    expect(screen.getByText(/no product sales data yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    render(<TopProductsWidget products={[]} loading={false} error={new Error('Products error')} onRetry={onRetry} />);
    expect(screen.getByText('Products error')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });
});
