import { describe, it, expect } from 'vitest';
import {
  renderTemplateString,
  renderBuiltinTemplate,
  BUILTIN_TEMPLATES,
} from '@/services/templateService';
import { NOTIFICATION_EVENTS } from '@/models/notification';

describe('templateService', () => {
  it('replaces variables and blanks missing keys', () => {
    expect(renderTemplateString('Hi {{name}}, order {{order_number}}', {
      name: 'Sam',
      order_number: 'ABC',
    })).toBe('Hi Sam, order ABC');
    expect(renderTemplateString('X {{missing}} Y', {})).toBe('X  Y');
  });

  it('renders built-in order confirmation', () => {
    const rendered = renderBuiltinTemplate(
      NOTIFICATION_EVENTS.ORDER_CREATED,
      'email',
      { name: 'Sam', order_number: 'ORD1', amount: '100', currency: 'KES' },
    );
    expect(rendered.subject).toContain('ORD1');
    expect(rendered.body).toContain('Sam');
    expect(rendered.body).toContain('100');
  });

  it('covers required event templates', () => {
    const codes = new Set(BUILTIN_TEMPLATES.map((t) => t.code));
    expect(codes.has(NOTIFICATION_EVENTS.WELCOME)).toBe(true);
    expect(codes.has(NOTIFICATION_EVENTS.PAYMENT_SUCCESSFUL)).toBe(true);
    expect(codes.has(NOTIFICATION_EVENTS.ADMIN_LOW_INVENTORY)).toBe(true);
  });
});
