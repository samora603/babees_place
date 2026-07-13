import { describe, it, expect, beforeEach } from 'vitest';
import {
  createMockEmailProvider,
  clearMockEmailOutbox,
  getMockEmailOutbox,
} from '@/services/providers/mockEmailProvider';
import {
  createMockSmsProvider,
  clearMockSmsOutbox,
  getMockSmsOutbox,
} from '@/services/providers/mockSmsProvider';
import { createStubPushProvider } from '@/services/providers/stubPushProvider';
import { getProviderForChannel } from '@/services/providers/notificationProviderFactory';
import { shouldDeliverChannel } from '@/services/notificationPreferenceService';

describe('notification providers', () => {
  beforeEach(() => {
    clearMockEmailOutbox();
    clearMockSmsOutbox();
  });

  it('mock email records sends', async () => {
    const provider = createMockEmailProvider();
    const result = await provider.send({
      to: 'a@b.com',
      subject: 'Hi',
      body: 'Hello',
      eventType: 'welcome',
    });
    expect(result.ok).toBe(true);
    expect(getMockEmailOutbox()).toHaveLength(1);
  });

  it('mock sms requires phone', async () => {
    const provider = createMockSmsProvider();
    const missing = await provider.send({ body: 'x', eventType: 'order_created' });
    expect(missing.ok).toBe(false);
    const ok = await provider.send({ to: '254700000000', body: 'x', eventType: 'order_created' });
    expect(ok.ok).toBe(true);
    expect(getMockSmsOutbox()).toHaveLength(1);
  });

  it('push stub skips', async () => {
    const result = await createStubPushProvider().send({ body: 'hi' });
    expect(result.skipped).toBe(true);
    expect(result.ok).toBe(false);
  });

  it('factory returns channel providers', () => {
    expect(getProviderForChannel('email').channel).toBe('email');
    expect(getProviderForChannel('sms').channel).toBe('sms');
    expect(getProviderForChannel('in_app').channel).toBe('in_app');
  });

  it('respects preference gating', () => {
    const prefs = {
      emailEnabled: true,
      smsEnabled: false,
      inAppEnabled: true,
      marketingEmails: false,
      orderUpdates: true,
      paymentUpdates: false,
    };
    expect(shouldDeliverChannel(prefs, 'email', 'order_created')).toBe(true);
    expect(shouldDeliverChannel(prefs, 'sms', 'order_created')).toBe(false);
    expect(shouldDeliverChannel(prefs, 'email', 'payment_successful')).toBe(false);
    expect(shouldDeliverChannel(prefs, 'email', 'welcome')).toBe(false);
  });
});
