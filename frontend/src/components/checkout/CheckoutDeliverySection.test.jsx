import { describe, it, expect, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import CheckoutDeliverySection from './CheckoutDeliverySection';

vi.mock('@/components/profile/AddressForm', () => ({
  default: ({ form, onChange }) => (
    <div data-testid="address-form">
      <input
        aria-label="Street"
        value={form.streetAddress}
        onChange={(e) => onChange('streetAddress', e.target.value)}
      />
    </div>
  ),
}));

const savedAddresses = [
  {
    id: 'addr-1',
    label: 'home',
    streetAddress: '123 Main',
    town: 'Westlands',
    isDefault: true,
  },
];

describe('CheckoutDeliverySection', () => {
  it('shows empty state when no saved addresses', () => {
    render(
      <CheckoutDeliverySection
        savedAddresses={[]}
        addressMode="once"
        onAddressModeChange={() => {}}
        selectedAddressId=""
        onSelectSavedAddress={() => {}}
        deliveryAddress={{ line1: '', line2: '', city: '', phone: '', notes: '' }}
        onDeliveryAddressChange={() => {}}
        newAddressForm={{}}
        onNewAddressFieldChange={() => {}}
        saveNewAddress={false}
        onSaveNewAddressChange={() => {}}
      />,
    );
    expect(screen.getByText(/No saved addresses yet/i)).toBeInTheDocument();
  });

  it('renders saved address options and one-time mode', async () => {
    const user = userEvent.setup();
    const onModeChange = vi.fn();

    render(
      <CheckoutDeliverySection
        savedAddresses={savedAddresses}
        addressMode="saved"
        onAddressModeChange={onModeChange}
        selectedAddressId="addr-1"
        onSelectSavedAddress={() => {}}
        deliveryAddress={{ line1: '', line2: '', city: '', phone: '', notes: '' }}
        onDeliveryAddressChange={() => {}}
        newAddressForm={{}}
        onNewAddressFieldChange={() => {}}
        saveNewAddress
        onSaveNewAddressChange={() => {}}
      />,
    );

    expect(screen.getByLabelText(/Select saved address/i)).toBeInTheDocument();
    await user.click(screen.getByLabelText(/Enter a one-time address/i));
    expect(onModeChange).toHaveBeenCalledWith('once');
  });

  it('shows new address form in new mode', () => {
    render(
      <CheckoutDeliverySection
        savedAddresses={savedAddresses}
        addressMode="new"
        onAddressModeChange={() => {}}
        selectedAddressId=""
        onSelectSavedAddress={() => {}}
        deliveryAddress={{ line1: '', line2: '', city: '', phone: '', notes: '' }}
        onDeliveryAddressChange={() => {}}
        newAddressForm={{ streetAddress: '' }}
        onNewAddressFieldChange={() => {}}
        saveNewAddress
        onSaveNewAddressChange={() => {}}
      />,
    );
    expect(screen.getByTestId('address-form')).toBeInTheDocument();
    expect(screen.getByLabelText(/Save this address to my account/i)).toBeInTheDocument();
  });
});
