/**
 * Built-in notification templates (fallback when DB templates unavailable).
 * Variables use {{name}} placeholders.
 */

import { NOTIFICATION_EVENTS } from '@/models/notification';

/** @type {Array<{ code: string, channel: string, subject: string|null, body: string }>} */
export const BUILTIN_TEMPLATES = [
  {
    code: NOTIFICATION_EVENTS.ACCOUNT_REGISTRATION,
    channel: 'in_app',
    subject: null,
    body: 'Welcome to Babees Place, {{name}}! Your account is ready.',
  },
  {
    code: NOTIFICATION_EVENTS.WELCOME,
    channel: 'email',
    subject: 'Welcome to Babees Place',
    body: 'Hi {{name}},\n\nWelcome to Babees Place. Start exploring our collection today.',
  },
  {
    code: NOTIFICATION_EVENTS.PASSWORD_RESET,
    channel: 'email',
    subject: 'Reset your Babees Place password',
    body: 'Hi {{name}},\n\nUse this link to reset your password: {{reset_link}}',
  },
  {
    code: NOTIFICATION_EVENTS.EMAIL_VERIFICATION,
    channel: 'email',
    subject: 'Verify your Babees Place email',
    body: 'Hi {{name}},\n\nPlease verify your email: {{verify_link}}',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_CREATED,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} was placed successfully. Total: {{amount}} {{currency}}.',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_CREATED,
    channel: 'email',
    subject: 'Order confirmation — {{order_number}}',
    body: 'Hi {{name}},\n\nThanks for your order {{order_number}}. Total: {{amount}} {{currency}}.',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_CONFIRMED,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} has been confirmed and is being prepared.',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_CANCELLED,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} has been cancelled.',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_READY_FOR_PICKUP,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} is ready for pickup at {{location}}.',
  },
  {
    code: NOTIFICATION_EVENTS.ORDER_READY_FOR_PICKUP,
    channel: 'sms',
    subject: null,
    body: 'Babees Place: Order {{order_number}} is ready for pickup.',
  },
  {
    code: NOTIFICATION_EVENTS.OUT_FOR_DELIVERY,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} is out for delivery.',
  },
  {
    code: NOTIFICATION_EVENTS.DELIVERED,
    channel: 'in_app',
    subject: null,
    body: 'Order {{order_number}} has been delivered. Enjoy!',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_INITIATED,
    channel: 'in_app',
    subject: null,
    body: 'Payment of {{amount}} {{currency}} initiated for order {{order_number}}. Check your phone for M-Pesa.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL,
    channel: 'in_app',
    subject: null,
    body: 'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL,
    channel: 'email',
    subject: 'Payment received — {{order_number}}',
    body: 'Hi {{name}},\n\nWe received your payment for {{order_number}}. Receipt: {{receipt_number}}.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL,
    channel: 'sms',
    subject: null,
    body: 'Babees Place: Payment confirmed for {{order_number}}. Receipt {{receipt_number}}.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_FAILED,
    channel: 'in_app',
    subject: null,
    body: 'Payment for order {{order_number}} failed. You can retry from your order page.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_FAILED,
    channel: 'email',
    subject: 'Payment failed — {{order_number}}',
    body: 'Hi {{name}},\n\nPayment for {{order_number}} did not complete. Please retry from your orders.',
  },
  {
    code: NOTIFICATION_EVENTS.PAYMENT_RETRY,
    channel: 'in_app',
    subject: null,
    body: 'A new payment attempt was started for order {{order_number}}.',
  },
  {
    code: NOTIFICATION_EVENTS.ADMIN_NEW_ORDER,
    channel: 'in_app',
    subject: null,
    body: 'New order {{order_number}} — {{amount}} {{currency}} ({{payment_method}}).',
  },
  {
    code: NOTIFICATION_EVENTS.ADMIN_LOW_INVENTORY,
    channel: 'in_app',
    subject: null,
    body: 'Low stock: {{product_name}} has {{stock}} units left.',
  },
  {
    code: NOTIFICATION_EVENTS.ADMIN_PAYMENT_RECEIVED,
    channel: 'in_app',
    subject: null,
    body: 'Payment received for order {{order_number}}. Receipt: {{receipt_number}}.',
  },
];

/**
 * Replace {{key}} placeholders. Missing keys become empty string.
 * @param {string} template
 * @param {Record<string, string|number|null|undefined>} vars
 */
export function renderTemplateString(template, vars = {}) {
  if (!template) return '';
  return String(template).replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, key) => {
    const value = vars[key];
    return value == null ? '' : String(value);
  });
}

/**
 * @param {string} code
 * @param {string} channel
 * @param {Record<string, string|number|null|undefined>} vars
 * @param {{ subject?: string|null, body?: string } | null} [override]
 */
export function renderBuiltinTemplate(code, channel, vars = {}, override = null) {
  const found = BUILTIN_TEMPLATES.find((t) => t.code === code && t.channel === channel);
  const subjectSrc = override?.subject ?? found?.subject ?? null;
  const bodySrc = override?.body ?? found?.body ?? `${code}`;
  return {
    code,
    channel,
    subject: subjectSrc ? renderTemplateString(subjectSrc, vars) : null,
    body: renderTemplateString(bodySrc, vars),
  };
}
