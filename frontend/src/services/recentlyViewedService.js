/**
 * Guest-friendly recently viewed products (localStorage).
 * Newest first, max 12, deduped by product id.
 */

const STORAGE_KEY = 'babees_recently_viewed_v1';
export const RECENTLY_VIEWED_LIMIT = 12;

const memoryFallback = { items: [] };

function canUseStorage() {
  try {
    if (typeof window === 'undefined' || !window.localStorage) return false;
    const probe = '__rv_probe__';
    window.localStorage.setItem(probe, '1');
    window.localStorage.removeItem(probe);
    return true;
  } catch {
    return false;
  }
}

function readRaw() {
  if (!canUseStorage()) return memoryFallback.items;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeRaw(items) {
  if (!canUseStorage()) {
    memoryFallback.items = items;
    return;
  }
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
  } catch (err) {
    console.warn('recentlyViewedService: storage write failed', err);
    memoryFallback.items = items;
  }
}

/**
 * Normalize a product snapshot for local persistence (lightweight).
 * @param {object} product
 */
export function toViewedSnapshot(product) {
  if (!product) return null;
  const id = product.id || product._id;
  if (!id) return null;

  return {
    id: String(id),
    name: product.name || '',
    slug: product.slug || null,
    price: product.price ?? null,
    discount_price: product.discount_price ?? null,
    image_url: product.image_url || null,
    images: Array.isArray(product.images) ? product.images.slice(0, 1) : [],
    category_id: product.category_id || product.categories?.id || null,
    categories: product.categories
      ? { id: product.categories.id, name: product.categories.name, slug: product.categories.slug }
      : null,
    stock: product.stock ?? null,
    is_active: product.is_active !== false,
    brand: product.brand || null,
    viewedAt: new Date().toISOString(),
  };
}

/**
 * @returns {object[]} newest first
 */
export function getRecentlyViewed() {
  const items = readRaw()
    .filter((item) => item && item.id)
    .slice(0, RECENTLY_VIEWED_LIMIT);
  return items;
}

/**
 * Record a product view. Moves existing entry to the front.
 * @param {object} product
 * @returns {object[]} updated list
 */
export function trackView(product) {
  const snapshot = toViewedSnapshot(product);
  if (!snapshot) return getRecentlyViewed();

  const existing = readRaw().filter((item) => item && String(item.id) !== snapshot.id);
  const next = [snapshot, ...existing].slice(0, RECENTLY_VIEWED_LIMIT);
  writeRaw(next);
  return next;
}

export function clearRecentlyViewed() {
  writeRaw([]);
  memoryFallback.items = [];
}

export const recentlyViewedService = {
  getRecentlyViewed,
  trackView,
  clearRecentlyViewed,
  toViewedSnapshot,
  RECENTLY_VIEWED_LIMIT,
};
