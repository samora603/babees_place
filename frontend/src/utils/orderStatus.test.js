import { describe, it, expect } from 'vitest';
import {
  getAllowedNextStatuses,
  canCustomerCancel,
  canAdminCancel,
  isTransitionAllowed,
  getTimelineSteps,
  DELIVERY_FEE,
} from './orderStatus';

describe('getAllowedNextStatuses', () => {
  it('pending can move to confirmed', () => {
    expect(getAllowedNextStatuses('pending', 'delivery')).toEqual(['confirmed']);
  });

  it('confirmed delivery path goes to processing', () => {
    expect(getAllowedNextStatuses('confirmed', 'delivery')).toEqual(['processing']);
  });

  it('confirmed pickup path goes to ready_for_pickup', () => {
    expect(getAllowedNextStatuses('confirmed', 'pickup')).toEqual(['ready_for_pickup']);
  });

  it('processing goes to shipped', () => {
    expect(getAllowedNextStatuses('processing', 'delivery')).toEqual(['shipped']);
  });

  it('delivered has no next statuses', () => {
    expect(getAllowedNextStatuses('delivered', 'delivery')).toEqual([]);
  });
});

describe('canCustomerCancel', () => {
  it('allows pending and confirmed', () => {
    expect(canCustomerCancel('pending')).toBe(true);
    expect(canCustomerCancel('confirmed')).toBe(true);
  });

  it('blocks processing and delivered', () => {
    expect(canCustomerCancel('processing')).toBe(false);
    expect(canCustomerCancel('delivered')).toBe(false);
  });
});

describe('canAdminCancel', () => {
  it('allows non-terminal except delivered', () => {
    expect(canAdminCancel('shipped')).toBe(true);
    expect(canAdminCancel('delivered')).toBe(false);
    expect(canAdminCancel('cancelled')).toBe(false);
  });
});

describe('isTransitionAllowed', () => {
  it('validates delivery flow', () => {
    expect(isTransitionAllowed('pending', 'confirmed', 'delivery')).toBe(true);
    expect(isTransitionAllowed('pending', 'shipped', 'delivery')).toBe(false);
  });
});

describe('getTimelineSteps', () => {
  it('returns pickup timeline', () => {
    expect(getTimelineSteps('pickup')).toContain('ready_for_pickup');
  });

  it('returns delivery timeline', () => {
    expect(getTimelineSteps('delivery')).toContain('shipped');
  });
});

describe('DELIVERY_FEE', () => {
  it('is 200 KES', () => {
    expect(DELIVERY_FEE).toBe(200);
  });
});
