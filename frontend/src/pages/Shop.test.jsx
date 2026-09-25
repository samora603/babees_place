import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';

const getProductsMock = vi.fn();
const getCategoriesMock = vi.fn();

vi.mock('@/services/productService', () => ({
  productService: {
    getProducts: (...args) => getProductsMock(...args),
    getCategories: (...args) => getCategoriesMock(...args),
  },
}));

vi.mock('@/components/products/ProductGrid', () => ({
  default: () => null,
}));

import Shop from './Shop';

describe('Shop search', () => {
  beforeEach(() => {
    getProductsMock.mockReset();
    getCategoriesMock.mockReset();
    getCategoriesMock.mockResolvedValue({ data: { data: [] }, error: null });
  });

  it('reads search from URL and fetches matching products', async () => {
    getProductsMock.mockResolvedValue({
      data: { data: [{ id: '1', name: 'Samsung Phone' }], total: 1, pages: 1 },
      error: null,
    });

    render(
      <MemoryRouter initialEntries={['/shop?search=phone']}>
        <Shop />
      </MemoryRouter>,
    );

    await waitFor(() => {
      expect(getProductsMock).toHaveBeenCalledWith(
        expect.objectContaining({ search: 'phone' }),
      );
    });

    expect(await screen.findByText(/1 piece found for “phone”/i)).toBeInTheDocument();
  });

  it('shows empty-results state for a successful zero-match search', async () => {
    getProductsMock.mockResolvedValue({
      data: { data: [], total: 0, pages: 1 },
      error: null,
    });

    render(
      <MemoryRouter initialEntries={['/shop?search=xyzabc123']}>
        <Shop />
      </MemoryRouter>,
    );

    expect(
      await screen.findByText(/No products found for “xyzabc123”/i),
    ).toBeInTheDocument();
  });

  it('shows load error instead of zero-result messaging when getProducts fails', async () => {
    getProductsMock.mockResolvedValue({
      data: { data: [], total: 0, pages: 1 },
      error: new Error('query failed'),
    });

    render(
      <MemoryRouter initialEntries={['/shop?search=phone']}>
        <Shop />
      </MemoryRouter>,
    );

    expect(
      await screen.findByText(/We couldn't load products right now. Please try again./i),
    ).toBeInTheDocument();
    expect(screen.queryByText(/No products found for/i)).not.toBeInTheDocument();
  });

  it('retries loading after a query failure', async () => {
    getProductsMock
      .mockResolvedValueOnce({
        data: { data: [], total: 0, pages: 1 },
        error: new Error('query failed'),
      })
      .mockResolvedValueOnce({
        data: { data: [{ id: '1', name: 'Phone Case' }], total: 1, pages: 1 },
        error: null,
      });

    const user = userEvent.setup();

    render(
      <MemoryRouter initialEntries={['/shop?search=phone']}>
        <Shop />
      </MemoryRouter>,
    );

    expect(
      await screen.findByText(/We couldn't load products right now. Please try again./i),
    ).toBeInTheDocument();

    await user.click(screen.getByRole('button', { name: 'Retry' }));

    await waitFor(() => {
      expect(getProductsMock).toHaveBeenCalledTimes(2);
    });
    expect(await screen.findByText(/1 piece found for “phone”/i)).toBeInTheDocument();
  });
});
