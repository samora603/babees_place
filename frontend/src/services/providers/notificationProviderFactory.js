/**
 * Notification channel provider factory (Workstream 7).
 *
 * LIVE INTEGRATION POINTS:
 * - Email: implement resendEmailProvider / sendgrid / smtp — set VITE_EMAIL_PROVIDER
 * - SMS: implement africastalkingSmsProvider / twilio — set VITE_SMS_PROVIDER
 * - Push: implement webPushProvider later — set VITE_PUSH_PROVIDER (interface only today)
 *
 * Secrets belong on Edge Functions / server — never in Vite env.
 */

import { createMockEmailProvider } from '@/services/providers/mockEmailProvider';
import { createResendEmailProvider } from '@/services/providers/resendEmailProvider';
import { createMockSmsProvider } from '@/services/providers/mockSmsProvider';
import { createAfricasTalkingSmsProvider } from '@/services/providers/africasTalkingSmsProvider';
import { createTwilioSmsProvider } from '@/services/providers/twilioSmsProvider';
import { createStubPushProvider } from '@/services/providers/stubPushProvider';
import { createInAppProvider } from '@/services/providers/inAppProvider';

/**
 * @typedef {Object} NotificationSendRequest
 * @property {string} eventType
 * @property {string} [userId]
 * @property {string} [to] email or phone
 * @property {string} [subject]
 * @property {string} body
 * @property {object} [metadata]
 */

/**
 * @typedef {Object} NotificationSendResult
 * @property {boolean} ok
 * @property {string} [externalId]
 * @property {string} [error]
 * @property {object} [raw]
 * @property {boolean} [skipped]
 */

/**
 * @typedef {Object} NotificationChannelProvider
 * @property {string} id
 * @property {'email'|'sms'|'push'|'in_app'} channel
 * @property {(req: NotificationSendRequest) => Promise<NotificationSendResult>} send
 */

export function getEmailProvider() {
  const mode = (import.meta.env.VITE_EMAIL_PROVIDER || 'mock').toLowerCase();
  if (mode === 'resend') return createResendEmailProvider();
  return createMockEmailProvider();
}

export function getSmsProvider() {
  const mode = (import.meta.env.VITE_SMS_PROVIDER || 'mock').toLowerCase();
  if (mode === 'africastalking' || mode === 'africa') return createAfricasTalkingSmsProvider();
  if (mode === 'twilio') return createTwilioSmsProvider();
  return createMockSmsProvider();
}

export function getPushProvider() {
  const mode = (import.meta.env.VITE_PUSH_PROVIDER || 'stub').toLowerCase();
  return createStubPushProvider(mode);
}

export function getInAppProvider() {
  return createInAppProvider();
}

/**
 * @param {'email'|'sms'|'push'|'in_app'} channel
 * @returns {NotificationChannelProvider}
 */
export function getProviderForChannel(channel) {
  switch (channel) {
    case 'email':
      return getEmailProvider();
    case 'sms':
      return getSmsProvider();
    case 'push':
      return getPushProvider();
    case 'in_app':
    default:
      return getInAppProvider();
  }
}

export const notificationProviderFactory = {
  getEmailProvider,
  getSmsProvider,
  getPushProvider,
  getInAppProvider,
  getProviderForChannel,
};
