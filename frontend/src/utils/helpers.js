/**
 * Format number as Kenyan Shillings
 * @param {number} amount
 * @returns {string} e.g. "KES 1,250"
 */
export const formatCurrency = (amount) =>
    `KES ${Number(amount).toLocaleString('en-KE', { minimumFractionDigits: 0 })}`;

/**
 * Truncate text to maxLength characters
 */
export const truncate = (text, maxLength = 100) =>
    text?.length > maxLength ? `${text.slice(0, maxLength)}…` : text;

/**
 * Format date string
 */
export const formatDate = (dateStr) =>
    new Date(dateStr).toLocaleDateString('en-KE', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
    });

/**
 * Format date + time
 */
export const formatDateTime = (dateStr) =>
    new Date(dateStr).toLocaleString('en-KE', {
        day: 'numeric',
        month: 'short',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
    });

/**
 * Get first image URL from a product's images array
 */
export const getPrimaryImage = (images = []) =>
    images.find((img) => img.isPrimary)?.url || images[0]?.url || '/placeholder.png';

/**
 * Calculate discount percentage
 */
export const discountPercent = (original, discounted) =>
    original > 0 ? Math.round(((original - discounted) / original) * 100) : 0;

/**
 * Normalize phone to E.164 +254 format
 */
export const normalizePhone = (phone) => {
    const cleaned = phone.replace(/\s+/g, '');
    if (cleaned.startsWith('+254')) return cleaned;
    if (cleaned.startsWith('254')) return `+${cleaned}`;
    if (cleaned.startsWith('0')) return `+254${cleaned.slice(1)}`;
    return phone;
};
