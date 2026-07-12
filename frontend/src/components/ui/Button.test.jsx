import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import Button from './Button';

describe('Button', () => {
  it('renders its children', () => {
    render(<Button>Sign In</Button>);
    expect(screen.getByRole('button', { name: /sign in/i })).toBeInTheDocument();
  });

  it('is disabled while loading', () => {
    render(<Button loading>Sign In</Button>);
    expect(screen.getByRole('button', { name: /sign in/i })).toBeDisabled();
  });

  it('fires onClick when pressed', async () => {
    const onClick = vi.fn();
    render(<Button onClick={onClick}>Press</Button>);
    await userEvent.click(screen.getByRole('button', { name: /press/i }));
    expect(onClick).toHaveBeenCalledTimes(1);
  });
});
