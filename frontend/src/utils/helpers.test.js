import { describe, it, expect } from 'vitest';
import {
  formatCurrency,
  truncate,
  getPrimaryImage,
  discountPercent,
  normalizePhone,
} from './helpers';

describe('formatCurrency', () => {
  it('formats a number as KES with thousands separators', () => {
    expect(formatCurrency(1250)).toBe('KES 1,250');
  });

  it('handles zero', () => {
    expect(formatCurrency(0)).toBe('KES 0');
  });
});

describe('truncate', () => {
  it('leaves short strings untouched', () => {
    expect(truncate('hello', 100)).toBe('hello');
  });

  it('truncates long strings and appends an ellipsis', () => {
    const result = truncate('abcdefghij', 5);
    expect(result).toBe('abcde…');
  });
});

describe('getPrimaryImage', () => {
  it('prefers the primary image', () => {
    const images = [{ url: 'a.png' }, { url: 'b.png', isPrimary: true }];
    expect(getPrimaryImage(images)).toBe('b.png');
  });

  it('falls back to the first image', () => {
    expect(getPrimaryImage([{ url: 'a.png' }])).toBe('a.png');
  });

  it('falls back to the placeholder when empty', () => {
    expect(getPrimaryImage([])).toBe('/placeholder.png');
  });
});

describe('discountPercent', () => {
  it('computes the rounded discount percentage', () => {
    expect(discountPercent(1000, 750)).toBe(25);
  });

  it('returns 0 when the original price is not positive', () => {
    expect(discountPercent(0, 0)).toBe(0);
  });
});

describe('normalizePhone', () => {
  it('converts a leading zero to +254', () => {
    expect(normalizePhone('0712345678')).toBe('+254712345678');
  });

  it('prefixes a 254 number with +', () => {
    expect(normalizePhone('254712345678')).toBe('+254712345678');
  });

  it('leaves an already-normalized number unchanged', () => {
    expect(normalizePhone('+254712345678')).toBe('+254712345678');
  });
});
