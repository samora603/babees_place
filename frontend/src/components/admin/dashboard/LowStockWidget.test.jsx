import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import LowStockWidget from './LowStockWidget';

const sampleProducts = [{
  id: 'prod-uuid-aaaa',
  name: 'Royal Jelly',
  sku: 'PROD-UUI',
  stock: 0,
  threshold: 5,
  severity: 'out',
}];

function renderWidget(props = {}) {
  return render(
    <MemoryRouter initialEntries={['/admin']}>
      <Routes>
        <Route
          path="/admin"
          element={(
            <LowStockWidget
              products={sampleProducts}
              loading={false}
              error={null}
              {...props}
            />
          )}
        />
        <Route path="/admin/products/:id/edit" element={<div>Product Edit</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('LowStockWidget', () => {
  it('renders low-stock product with severity label', () => {
    renderWidget();
    expect(screen.getByText('Royal Jelly')).toBeInTheDocument();
    expect(screen.getByText('Out of Stock')).toBeInTheDocument();
    expect(screen.getByText('PROD-UUI')).toBeInTheDocument();
  });

  it('shows empty state when no products', () => {
    renderWidget({ products: [] });
    expect(screen.getByText(/above the low-stock threshold/i)).toBeInTheDocument();
  });

  it('shows error state', () => {
    renderWidget({ products: [], error: new Error('Stock fetch failed') });
    expect(screen.getByText('Stock fetch failed')).toBeInTheDocument();
  });

  it('navigates to product edit on row click', async () => {
    renderWidget();
    await userEvent.click(screen.getByRole('link', { name: /edit product royal jelly/i }));
    expect(await screen.findByText('Product Edit')).toBeInTheDocument();
  });
});
