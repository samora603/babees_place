import { describe, it, expect } from 'vitest';
import { generateSlug, isValidSlug, appendSlugSuffix, isUuid, UUID_RE } from './slug';

describe('generateSlug', () => {
  it('lowercases and hyphenates a product name', () => {
    expect(generateSlug('Acoustic Guitar')).toBe('acoustic-guitar');
  });

  it('strips special characters', () => {
    expect(generateSlug('Hello & World!')).toBe('hello-world');
  });

  it('returns empty string for invalid input', () => {
    expect(generateSlug('')).toBe('');
    expect(generateSlug(null)).toBe('');
  });
});

describe('isValidSlug', () => {
  it('accepts valid slugs', () => {
    expect(isValidSlug('acoustic-guitar')).toBe(true);
    expect(isValidSlug('item123')).toBe(true);
  });

  it('rejects invalid slugs', () => {
    expect(isValidSlug('')).toBe(false);
    expect(isValidSlug('Has Spaces')).toBe(false);
    expect(isValidSlug('UPPER')).toBe(false);
  });
});

describe('appendSlugSuffix', () => {
  it('appends a suffix for uniqueness', () => {
    expect(appendSlugSuffix('guitar', 'abc12345')).toBe('guitar-abc12345');
  });
});

describe('isUuid', () => {
  it('detects UUID format', () => {
    expect(isUuid('550e8400-e29b-41d4-a716-446655440000')).toBe(true);
    expect(UUID_RE.test('550e8400-e29b-41d4-a716-446655440000')).toBe(true);
  });

  it('rejects non-UUID strings', () => {
    expect(isUuid('acoustic-guitar')).toBe(false);
    expect(isUuid('')).toBe(false);
  });
});
