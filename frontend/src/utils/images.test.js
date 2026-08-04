import { describe, it, expect } from 'vitest';
import {
  validateImageFile,
  validateImageFiles,
  normalizeGalleryImages,
  setPrimaryAt,
  removeImageAt,
  mergeUploadedImages,
  getImageAtIndex,
  MAX_IMAGE_BYTES,
  ALLOWED_IMAGE_TYPES,
} from './images';

describe('validateImageFile', () => {
  it('accepts allowed MIME types under size limit', () => {
    const file = { name: 'photo.jpg', type: 'image/jpeg', size: 1024 };
    expect(validateImageFile(file).valid).toBe(true);
  });

  it('rejects disallowed types', () => {
    const file = { name: 'doc.pdf', type: 'application/pdf', size: 1024 };
    expect(validateImageFile(file).valid).toBe(false);
  });

  it('rejects files over 5 MB', () => {
    const file = { name: 'big.png', type: 'image/png', size: MAX_IMAGE_BYTES + 1 };
    expect(validateImageFile(file).valid).toBe(false);
  });

  it('validates multiple files', () => {
    const files = ALLOWED_IMAGE_TYPES.map((type, i) => ({
      name: `f${i}.webp`,
      type,
      size: 100,
    }));
    expect(validateImageFiles(files).valid).toBe(true);
  });
});

describe('normalizeGalleryImages', () => {
  it('marks first image primary when none set', () => {
    const result = normalizeGalleryImages([{ url: 'a.png' }, { url: 'b.png' }]);
    expect(result[0].isPrimary).toBe(true);
    expect(result[1].isPrimary).toBe(false);
  });

  it('preserves explicit primary', () => {
    const result = normalizeGalleryImages([
      { url: 'a.png' },
      { url: 'b.png', isPrimary: true },
    ]);
    expect(result[1].isPrimary).toBe(true);
  });
});

describe('setPrimaryAt', () => {
  it('sets primary at given index', () => {
    const images = [{ url: 'a.png', isPrimary: true }, { url: 'b.png' }];
    const next = setPrimaryAt(images, 1);
    expect(next[1].isPrimary).toBe(true);
    expect(next[0].isPrimary).toBe(false);
  });
});

describe('removeImageAt', () => {
  it('removes image and promotes new primary', () => {
    const images = [{ url: 'a.png', isPrimary: true }, { url: 'b.png' }];
    const next = removeImageAt(images, 0);
    expect(next).toHaveLength(1);
    expect(next[0].isPrimary).toBe(true);
  });
});

describe('mergeUploadedImages', () => {
  it('appends uploads without dropping existing', () => {
    const existing = [{ url: 'old.png', isPrimary: true }];
    const uploaded = [{ url: 'new.png', path: 'products/x/new.png' }];
    const merged = mergeUploadedImages(existing, uploaded);
    expect(merged).toHaveLength(2);
    expect(merged[0].url).toBe('old.png');
    expect(merged[1].url).toBe('new.png');
  });
});

describe('getImageAtIndex', () => {
  it('returns image at active index', () => {
    const images = [{ url: 'a.png' }, { url: 'b.png' }];
    expect(getImageAtIndex(images, 1)).toBe('/b.png');
  });

  it('falls back to placeholder when empty', () => {
    expect(getImageAtIndex([], 0)).toBe('/placeholder.png');
  });
});
