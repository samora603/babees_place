import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';

const navigateMock = vi.fn();
let mockLocation = { pathname: '/', search: '' };

vi.mock('react-router-dom', async (importOriginal) => {
  const actual = await importOriginal();
  return {
    ...actual,
    useNavigate: () => navigateMock,
    useLocation: () => mockLocation,
  };
});

vi.mock('@/context/AuthContext', () => ({
  useAuth: () => ({ user: null, profile: null, logout: vi.fn() }),
}));

vi.mock('@/context/CartContext', () => ({
  useCart: () => ({ itemCount: 0 }),
}));

vi.mock('@/components/notifications/NotificationBell', () => ({
  default: () => null,
}));

import Navbar from './Navbar';

function getSearchInput() {
  return screen.getByRole('searchbox', { name: 'Search products' });
}

describe('Navbar search', () => {
  beforeEach(() => {
    navigateMock.mockReset();
    mockLocation = { pathname: '/', search: '' };
  });

  it('submits search on Enter', async () => {
    const user = userEvent.setup();
    render(
      <MemoryRouter>
        <Navbar />
      </MemoryRouter>,
    );

    const input = getSearchInput();
    await user.type(input, 'phone{Enter}');

    expect(navigateMock).toHaveBeenCalledWith('/shop?search=phone');
  });

  it('submits search when magnifying glass is clicked', async () => {
    const user = userEvent.setup();
    render(
      <MemoryRouter>
        <Navbar />
      </MemoryRouter>,
    );

    const input = getSearchInput();
    await user.type(input, 'phone');
    await user.click(screen.getByRole('button', { name: 'Submit search' }));

    expect(navigateMock).toHaveBeenCalledWith('/shop?search=phone');
  });

  it('preserves existing Shop filters when searching from /shop', async () => {
    const user = userEvent.setup();
    mockLocation = { pathname: '/shop', search: '?category=electronics&sort=price' };

    render(
      <MemoryRouter>
        <Navbar />
      </MemoryRouter>,
    );

    const input = getSearchInput();
    await user.type(input, 'phone');
    await user.click(screen.getByRole('button', { name: 'Submit search' }));

    expect(navigateMock).toHaveBeenCalledTimes(1);
    const target = navigateMock.mock.calls[0][0];
    expect(target).toMatch(/^\/shop\?/);
    const params = new URLSearchParams(target.split('?')[1]);
    expect(params.get('search')).toBe('phone');
    expect(params.get('category')).toBe('electronics');
    expect(params.get('sort')).toBe('price');
  });
});
