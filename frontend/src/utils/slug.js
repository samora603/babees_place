/** Slug helpers for products and categories. */

const SLUG_MAX = 80;

export function generateSlug(name) {
  if (!name || typeof name !== 'string') return '';
  return name
    .toLowerCase()
    .trim()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, SLUG_MAX);
}

export function isValidSlug(slug) {
  if (!slug) return false;
  return /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug);
}

export function appendSlugSuffix(slug, suffix) {
  const base = slug || 'item';
  const clean = String(suffix).replace(/[^a-z0-9]/gi, '').slice(0, 8).toLowerCase();
  return `${base}-${clean}`.slice(0, SLUG_MAX + 12);
}

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value) {
  return UUID_RE.test(String(value || ''));
}
