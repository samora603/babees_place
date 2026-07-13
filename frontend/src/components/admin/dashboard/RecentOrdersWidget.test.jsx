import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import RecentOrdersWidget from './RecentOrdersWidget';

const sampleOrders = [{
  id: 'order-uuid-1111',
  orderNumber: '#ORDER-UI',
  customerName: 'Jane Doe',
  status: 'pending',
  paymentStatus: 'pending',
  fulfillmentType: 'pickup',
  total: 1200,
  createdAt: '2026-07-13T09:00:00.000Z',
}];

function renderWidget(props = {}) {
  return render(
    <MemoryRouter initialEntries={['/admin']}>
      <Routes>
        <Route
          path="/admin"
          element={(
            <RecentOrdersWidget
              orders={sampleOrders}
              loading={false}
              error={null}
              {...props}
            />
          )}
        />
        <Route path="/admin/orders/:id" element={<div>Order Detail</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('RecentOrdersWidget', () => {
  it('renders order rows with badges', () => {
    renderWidget();
    expect(screen.getByText('#ORDER-UI')).toBeInTheDocument();
    expect(screen.getByText('Jane Doe')).toBeInTheDocument();
    expect(screen.getAllByText('Pending')).toHaveLength(2);
    expect(screen.getByText(/Campus Pickup/i)).toBeInTheDocument();
  });

  it('shows skeleton while loading', () => {
    renderWidget({ orders: [], loading: true });
    expect(screen.getByLabelText('Loading widget')).toBeInTheDocument();
  });

  it('shows empty state', () => {
    renderWidget({ orders: [] });
    expect(screen.getByText(/no orders yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    renderWidget({ orders: [], error: new Error('Network error'), onRetry });
    expect(screen.getByText('Network error')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });

  it('navigates to admin order detail on row click', async () => {
    renderWidget();
    await userEvent.click(screen.getByRole('link', { name: /view order #order-ui/i }));
    expect(await screen.findByText('Order Detail')).toBeInTheDocument();
  });
});
