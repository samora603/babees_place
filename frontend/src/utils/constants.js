export const ORDER_STATUSES = {
    pending: { label: 'Pending', color: 'text-yellow-400 bg-yellow-400/10' },
    processing: { label: 'Processing', color: 'text-purple-400 bg-purple-400/10' },
    shipped: { label: 'Shipped', color: 'text-cyan-400   bg-cyan-400/10' },
    delivered: { label: 'Delivered', color: 'text-green-400  bg-green-400/10' },
    cancelled: { label: 'Cancelled', color: 'text-red-400    bg-red-400/10' },
};

export const PAYMENT_STATUSES = {
    pending: { label: 'Pending', color: 'text-yellow-400 bg-yellow-400/10' },
    paid: { label: 'Paid', color: 'text-green-400  bg-green-400/10' },
    failed: { label: 'Failed', color: 'text-red-400    bg-red-400/10' },
    refunded: { label: 'Refunded', color: 'text-blue-400   bg-blue-400/10' },
};

export const DELIVERY_TYPES = {
    pickup: { label: 'Campus Pickup', icon: '🏫' },
    delivery: { label: 'Delivery', icon: '🚚' },
};

// Canonical profile roles (profiles.role): 'customer' | 'admin'.
export const ROLES = {
    customer: 'customer',
    admin: 'admin',
};

// Sorting is limited to columns that exist in the canonical products table.
export const SORT_OPTIONS = [
    { value: '-createdAt', label: 'Newest' },
    { value: 'price', label: 'Price: Low → High' },
    { value: '-price', label: 'Price: High → Low' },
];
