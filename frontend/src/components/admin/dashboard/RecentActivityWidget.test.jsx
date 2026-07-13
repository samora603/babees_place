import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import RecentActivityWidget from './RecentActivityWidget';

const sampleEvents = [{
  id: 'evt-1',
  orderId: 'order-uuid-2222',
  orderNumber: '#ORDER-22',
  eventType: 'order_placed',
  description: 'Order Created',
  iconKey: 'placed',
  userName: 'Sam',
  createdAt: '2026-07-13T09:00:00.000Z',
}];

function renderWidget(props = {}) {
  return render(
    <MemoryRouter initialEntries={['/admin']}>
      <Routes>
        <Route
          path="/admin"
          element={(
            <RecentActivityWidget
              events={sampleEvents}
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

describe('RecentActivityWidget', () => {
  it('renders activity event with description and user', () => {
    renderWidget();
    expect(screen.getByText('#ORDER-22')).toBeInTheDocument();
    expect(screen.getByText('Order Created')).toBeInTheDocument();
    expect(screen.getByText(/Sam ·/)).toBeInTheDocument();
  });

  it('shows loading skeleton', () => {
    renderWidget({ events: [], loading: true });
    expect(screen.getByLabelText('Loading widget')).toBeInTheDocument();
  });

  it('shows empty state', () => {
    renderWidget({ events: [] });
    expect(screen.getByText(/no order activity yet/i)).toBeInTheDocument();
  });

  it('shows error state with retry', async () => {
    const onRetry = vi.fn();
    renderWidget({ events: [], error: new Error('Activity unavailable'), onRetry });
    expect(screen.getByText('Activity unavailable')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    expect(onRetry).toHaveBeenCalled();
  });

  it('navigates to order detail on event click', async () => {
    renderWidget();
    await userEvent.click(screen.getByRole('button', { name: /#ORDER-22/i }));
    expect(await screen.findByText('Order Detail')).toBeInTheDocument();
  });
});
