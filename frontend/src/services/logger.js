/**
 * Structured logging abstraction (Workstream 9).
 * Levels: debug | info | warn | error | audit
 * Categories: app | error | payment | order | notification | audit
 *
 * Configure via VITE_LOG_LEVEL (default: info in prod, debug in dev).
 * Never log secrets (keys, tokens, full card/phone payloads).
 */

const LEVELS = { debug: 10, info: 20, warn: 30, error: 40, audit: 50, silent: 100 };

function resolveMinLevel() {
  const raw = (import.meta.env.VITE_LOG_LEVEL || '').toLowerCase();
  if (raw && LEVELS[raw] != null) return LEVELS[raw];
  return import.meta.env.PROD ? LEVELS.info : LEVELS.debug;
}

let minLevel = resolveMinLevel();

/** @type {Array<object>} */
const ringBuffer = [];
const RING_MAX = 200;

function pushRing(entry) {
  ringBuffer.push(entry);
  if (ringBuffer.length > RING_MAX) ringBuffer.shift();
}

function redact(value) {
  if (value == null) return value;
  if (typeof value === 'string') {
    if (/anon|service_role|apikey|secret|password|token/i.test(value) && value.length > 20) {
      return '[REDACTED]';
    }
    return value;
  }
  if (Array.isArray(value)) return value.map(redact);
  if (typeof value === 'object') {
    const out = {};
    for (const [k, v] of Object.entries(value)) {
      if (/password|secret|token|authorization|apikey|service_role/i.test(k)) {
        out[k] = '[REDACTED]';
      } else {
        out[k] = redact(v);
      }
    }
    return out;
  }
  return value;
}

/**
 * @param {'debug'|'info'|'warn'|'error'|'audit'} level
 * @param {'app'|'error'|'payment'|'order'|'notification'|'audit'} category
 * @param {string} message
 * @param {object} [meta]
 */
export function log(level, category, message, meta = {}) {
  const levelNum = LEVELS[level] ?? LEVELS.info;
  if (levelNum < minLevel) return;

  const entry = {
    ts: new Date().toISOString(),
    level,
    category,
    message,
    meta: redact(meta),
    env: import.meta.env.MODE,
  };

  pushRing(entry);

  const prefix = `[${entry.ts}] [${level.toUpperCase()}] [${category}]`;
  const payload = Object.keys(entry.meta || {}).length ? entry.meta : undefined;

  if (level === 'error') {
    console.error(prefix, message, payload ?? '');
  } else if (level === 'warn') {
    console.warn(prefix, message, payload ?? '');
  } else if (level === 'debug') {
    console.debug(prefix, message, payload ?? '');
  } else {
    console.info(prefix, message, payload ?? '');
  }

  return entry;
}

export const logger = {
  setLevel(level) {
    if (LEVELS[level] != null) minLevel = LEVELS[level];
  },
  getLevel() {
    return Object.entries(LEVELS).find(([, v]) => v === minLevel)?.[0] || 'info';
  },
  getRecentLogs() {
    return [...ringBuffer];
  },
  clear() {
    ringBuffer.length = 0;
  },
  debug: (cat, msg, meta) => log('debug', cat, msg, meta),
  info: (cat, msg, meta) => log('info', cat, msg, meta),
  warn: (cat, msg, meta) => log('warn', cat, msg, meta),
  error: (cat, msg, meta) => log('error', cat, msg, meta),
  audit: (msg, meta) => log('audit', 'audit', msg, meta),
  payment: (msg, meta) => log('info', 'payment', msg, meta),
  order: (msg, meta) => log('info', 'order', msg, meta),
  notification: (msg, meta) => log('info', 'notification', msg, meta),
};

export default logger;
