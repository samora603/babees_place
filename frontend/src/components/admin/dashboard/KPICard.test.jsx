import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import KPICard from './KPICard';

describe('KPICard', () => {
  it('renders label and formatted currency value', () => {
    render(
      <KPICard kpi={{ key: 'totalRevenue', label: 'Total Revenue', value: 1250, format: 'currency' }} />,
    );
    expect(screen.getByText('Total Revenue')).toBeInTheDocument();
    expect(screen.getByText('KES 1,250')).toBeInTheDocument();
  });

  it('renders formatted number value', () => {
    render(
      <KPICard kpi={{ key: 'totalOrders', label: 'Total Orders', value: 42, format: 'number' }} />,
    );
    expect(screen.getByText('Total Orders')).toBeInTheDocument();
    expect(screen.getByText('42')).toBeInTheDocument();
  });
});
