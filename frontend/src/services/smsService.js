import { getSmsProvider } from '@/services/providers/notificationProviderFactory';
import { renderBuiltinTemplate } from '@/services/templateService';

/**
 * SMS channel facade — Africa's Talking / Twilio swap via factory.
 */
export async function sendSms({ to, body, eventType, metadata }) {
  const provider = getSmsProvider();
  return provider.send({ to, body, eventType, metadata });
}

export async function sendTemplatedSms({ to, eventType, vars, metadata }) {
  const rendered = renderBuiltinTemplate(eventType, 'sms', vars);
  return sendSms({
    to,
    body: rendered.body,
    eventType,
    metadata,
  });
}

export const smsService = {
  sendSms,
  sendTemplatedSms,
};
