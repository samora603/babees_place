import { getEmailProvider } from '@/services/providers/notificationProviderFactory';
import { renderBuiltinTemplate } from '@/services/templateService';

/**
 * Email channel facade — never import Resend/SendGrid from UI.
 */
export async function sendEmail({ to, subject, body, eventType, metadata }) {
  const provider = getEmailProvider();
  return provider.send({ to, subject, body, eventType, metadata });
}

export async function sendTemplatedEmail({ to, eventType, vars, metadata }) {
  const rendered = renderBuiltinTemplate(eventType, 'email', vars);
  return sendEmail({
    to,
    subject: rendered.subject,
    body: rendered.body,
    eventType,
    metadata,
  });
}

export const emailService = {
  sendEmail,
  sendTemplatedEmail,
};
