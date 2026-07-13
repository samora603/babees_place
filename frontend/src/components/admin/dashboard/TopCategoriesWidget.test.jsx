import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import TopCategoriesWidget from './TopCategoriesWidget';

const categories = [{
  categoryName: 'Wellness',
  unitsSold: 8,
  revenue: 2400,
}];

describe('TopCategoriesWidget', () => {
  it('renders category rows with percentage bar', () => {
    render(<TopCategoriesWidget categories={categories} loading={false} error={null} />);
    expect(screen.getByText('Wellness')).toBeInTheDocument();
    expect(screen.getByText('8')).toBeInTheDocument();
    expect(screen.getByText('KES 2,400')).toBeInTheDocument();
    expect(screen.getByText('100%')).toBeInTheDocument();
    expect(screen.getByRole('progressbar', { name: /wellness share/i })).toBeInTheDocument();
  });

  it('shows empty state', () => {
    render(<TopCategoriesWidget categories={[]} loading={false} error={null} />);
    expect(screen.getByText(/no category sales data yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    render(<TopCategoriesWidget categories={[]} loading={false} error={new Error('Categories error')} onRetry={onRetry} />);
    expect(screen.getByText('Categories error')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });
});
