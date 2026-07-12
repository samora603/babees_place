import { DELIVERY_TYPES } from '@/utils/constants';
import { formatCurrency } from '@/utils/helpers';

export default function FulfillmentDetails({ order }) {
  if (!order) return null;

  const typeLabel = DELIVERY_TYPES[order.deliveryType]?.label || order.deliveryType;

  return (
    <div className="card p-5 space-y-3 text-sm">
      <h2 className="font-semibold">Fulfillment</h2>
      <p className="text-slate-400">
        Method: <strong className="text-slate-200">{typeLabel || '—'}</strong>
      </p>
      {order.deliveryFee > 0 && (
        <p className="text-slate-400">
          Delivery fee: <strong className="text-slate-200">{formatCurrency(order.deliveryFee)}</strong>
        </p>
      )}
      {order.deliveryType === 'pickup' && order.pickupLocation && (
        <div className="border-t border-surface-border pt-3 space-y-1">
          <p className="font-medium text-slate-200">{order.pickupLocation.name}</p>
          <p className="text-slate-400">{order.pickupLocation.building}</p>
          {order.pickupLocation.description && (
            <p className="text-slate-500 text-xs">{order.pickupLocation.description}</p>
          )}
          {order.pickupLocation.operatingHours && (
            <div className="text-xs text-slate-500 mt-2 grid grid-cols-2 gap-2">
              <div>
                Weekdays: {order.pickupLocation.operatingHours.weekdays?.open} – {order.pickupLocation.operatingHours.weekdays?.close}
              </div>
              <div>
                Weekends: {order.pickupLocation.operatingHours.weekends?.open} – {order.pickupLocation.operatingHours.weekends?.close}
              </div>
            </div>
          )}
          <p className="text-brand-400 text-xs mt-2">Bring your order number when collecting.</p>
        </div>
      )}
      {order.deliveryType === 'delivery' && order.deliveryAddress && (
        <div className="border-t border-surface-border pt-3 space-y-1">
          <p className="text-slate-200">{order.deliveryAddress.line1}</p>
          {order.deliveryAddress.line2 && <p className="text-slate-400">{order.deliveryAddress.line2}</p>}
          <p className="text-slate-400">{order.deliveryAddress.city}</p>
          <p className="text-slate-400">Phone: {order.deliveryAddress.phone}</p>
          {order.deliveryAddress.notes && (
            <p className="text-slate-500 text-xs">Notes: {order.deliveryAddress.notes}</p>
          )}
        </div>
      )}
      {order.customerNote && (
        <p className="text-slate-500 text-xs border-t border-surface-border pt-3">
          Your note: {order.customerNote}
        </p>
      )}
    </div>
  );
}
