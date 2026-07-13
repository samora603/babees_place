/**
 * Error reporting abstraction (Workstream 9).
 * Providers: console (default) | sentry stub | otel stub
 * Set VITE_ERROR_PROVIDER=sentry|otel and VITE_ERROR_DSN / edge URL when ready.
 */

import { logger } from '@/services/logger';

/**
 * @typedef {Object} ErrorReport
 * @property {string} message
 * @property {string} [name]
 * @property {string} [stack]
 * @property {string} [source]
 * @property {object} [context]
 * @property {string} [severity]
 */

function createConsoleProvider() {
  return {
    id: 'console',
    async capture(report) {
      logger.error('error', report.message, {
        name: report.name,
        source: report.source,
        context: report.context,
        stack: report.stack?.slice?.(0, 500),
      });
      return { ok: true };
    },
  };
}

/** Sentry stub — wire @sentry/react or Edge proxy later. */
function createSentryProvider() {
  const dsn = import.meta.env.VITE_SENTRY_DSN || '';
  return {
    id: 'sentry',
    async capture(report) {
      if (!dsn) {
        return createConsoleProvider().capture(report);
      }
      // LIVE: replace with Sentry.captureException
      logger.warn('error', 'Sentry provider stub — DSN set but SDK not wired', {
        message: report.message,
      });
      return { ok: true, stub: true };
    },
  };
}

/** OpenTelemetry stub */
function createOtelProvider() {
  return {
    id: 'otel',
    async capture(report) {
      logger.warn('error', 'OpenTelemetry provider stub', { message: report.message });
      return { ok: true, stub: true };
    },
  };
}

function getProvider() {
  const mode = (import.meta.env.VITE_ERROR_PROVIDER || 'console').toLowerCase();
  if (mode === 'sentry') return createSentryProvider();
  if (mode === 'otel' || mode === 'opentelemetry') return createOtelProvider();
  return createConsoleProvider();
}

function toReport(error, source, context = {}) {
  if (error instanceof Error) {
    return {
      message: error.message,
      name: error.name,
      stack: error.stack,
      source,
      context,
      severity: 'error',
    };
  }
  return {
    message: String(error),
    source,
    context,
    severity: 'error',
  };
}

export async function reportError(error, source = 'app', context = {}) {
  const report = toReport(error, source, context);
  try {
    return await getProvider().capture(report);
  } catch (err) {
    console.error('[errorReporting] provider failed', err);
    return { ok: false };
  }
}

let installed = false;

/**
 * Install global handlers once (window errors + unhandled rejections).
 */
export function installGlobalErrorHandlers() {
  if (installed || typeof window === 'undefined') return;
  installed = true;

  window.addEventListener('error', (event) => {
    reportError(event.error || event.message, 'window.onerror', {
      filename: event.filename,
      lineno: event.lineno,
      colno: event.colno,
    });
  });

  window.addEventListener('unhandledrejection', (event) => {
    reportError(event.reason || 'Unhandled rejection', 'unhandledrejection');
  });

  logger.info('app', 'Global error handlers installed');
}

export const errorReportingService = {
  reportError,
  installGlobalErrorHandlers,
  getProviderId: () => getProvider().id,
};
