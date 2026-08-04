/**
 * Canonical public site origin for SEO / OG / sitemap.
 * Trailing slashes are stripped. Falls back to window.origin in the browser,
 * then to empty string at build-time when unset (plugin uses a documented default).
 */
export function getSiteUrl() {
  const fromEnv = String(import.meta.env.VITE_SITE_URL || '').trim().replace(/\/$/, '');
  if (fromEnv) return fromEnv;
  if (typeof window !== 'undefined' && window.location?.origin) {
    return window.location.origin.replace(/\/$/, '');
  }
  return '';
}

/** Join site origin with a path that may already be absolute. */
export function absoluteUrl(pathOrUrl = '/') {
  if (!pathOrUrl) return getSiteUrl() || '/';
  if (/^https?:\/\//i.test(pathOrUrl)) return pathOrUrl;
  const base = getSiteUrl();
  const path = pathOrUrl.startsWith('/') ? pathOrUrl : `/${pathOrUrl}`;
  return base ? `${base}${path}` : path;
}
