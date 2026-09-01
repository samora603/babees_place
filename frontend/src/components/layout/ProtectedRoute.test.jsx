import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';

const useAuthMock = vi.fn();

vi.mock('@/context/AuthContext', () => ({
  useAuth: () => useAuthMock(),
}));

import ProtectedRoute from './ProtectedRoute';

function renderProtectedRoute(initialEntry = '/cart') {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <Routes>
        <Route element={<ProtectedRoute />}>
          <Route path="/cart" element={<div>Protected content</div>} />
        </Route>
        <Route path="/login" element={<div>Login page</div>} />
      </Routes>
    </MemoryRouter>,
  );
}

describe('ProtectedRoute', () => {
  beforeEach(() => {
    useAuthMock.mockReset();
  });

  it('shows a spinner while auth is initializing', () => {
    useAuthMock.mockReturnValue({ user: null, profile: null, loading: true });

    renderProtectedRoute();

    expect(screen.getByRole('status')).toBeInTheDocument();
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument();
  });

  it('redirects unauthenticated users to login', () => {
    useAuthMock.mockReturnValue({ user: null, profile: null, loading: false });

    renderProtectedRoute();

    expect(screen.getByText('Login page')).toBeInTheDocument();
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument();
  });

  it('waits for profile before rendering protected content', () => {
    useAuthMock.mockReturnValue({
      user: { id: 'user-1' },
      profile: null,
      loading: false,
    });

    renderProtectedRoute();

    expect(screen.getByRole('status')).toBeInTheDocument();
    expect(screen.queryByText('Protected content')).not.toBeInTheDocument();
  });

  it('renders protected content when user and profile are available', () => {
    useAuthMock.mockReturnValue({
      user: { id: 'user-1' },
      profile: { id: 'user-1', role: 'customer' },
      loading: false,
    });

    renderProtectedRoute();

    expect(screen.getByText('Protected content')).toBeInTheDocument();
  });
});
