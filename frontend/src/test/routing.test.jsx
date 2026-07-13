import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

// The Supabase client is created at module load and called on provider mount.
// Mock both client modules so startup/routing can be exercised without network.
vi.mock('@/lib/supabaseClient', async () => {
  const { createSupabaseMock } = await import('./supabaseMock');
  return { supabase: createSupabaseMock(), default: createSupabaseMock() };
});
vi.mock('@/lib/supabase', async () => {
  const { createSupabaseMock } = await import('./supabaseMock');
  return { supabase: createSupabaseMock(), default: createSupabaseMock() };
});

import App from '@/App';
import { AuthProvider } from '@/context/AuthContext';
import { CartProvider } from '@/context/CartContext';
import { WishlistProvider } from '@/context/WishlistContext';

function renderAt(path) {
  return render(
    <MemoryRouter initialEntries={[path]}>
      <AuthProvider>
        <CartProvider>
          <WishlistProvider>
            <App />
          </WishlistProvider>
        </CartProvider>
      </AuthProvider>
    </MemoryRouter>
  );
}

describe('application smoke test', () => {
  it('boots and renders the login page (auth entry point)', async () => {
    renderAt('/login');
    expect(await screen.findByText(/login to babis place/i)).toBeInTheDocument();
  });

  it('renders the register page (auth entry point)', async () => {
    renderAt('/register');
    expect(await screen.findByRole('button', { name: /create account/i })).toBeInTheDocument();
  });

  it('renders the 404 page for an unknown route', async () => {
    renderAt('/this-route-does-not-exist');
    expect(await screen.findByText(/page not found/i)).toBeInTheDocument();
  });
});
