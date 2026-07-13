/**
 * PWA service worker registration (opt-in).
 * Set VITE_ENABLE_SW=true to register /sw.js in production builds.
 * Offline mode is intentionally not fully implemented.
 */
export function registerServiceWorker() {
  if (typeof window === 'undefined' || !('serviceWorker' in navigator)) return;
  const enabled = String(import.meta.env.VITE_ENABLE_SW || '').toLowerCase() === 'true';
  if (!enabled || !import.meta.env.PROD) return;

  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch((err) => {
      console.warn('[pwa] SW registration failed', err);
    });
  });
}

/**
 * Install prompt readiness — listen for beforeinstallprompt without auto-showing.
 */
export function setupInstallPromptCapture(onAvailable) {
  if (typeof window === 'undefined') return () => {};
  const handler = (event) => {
    event.preventDefault();
    onAvailable?.(event);
  };
  window.addEventListener('beforeinstallprompt', handler);
  return () => window.removeEventListener('beforeinstallprompt', handler);
}
