/** Product image gallery helpers. */

export const MAX_IMAGE_BYTES = 5 * 1024 * 1024;
export const ALLOWED_IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/webp'];

export function validateImageFile(file) {
  if (!file) return { valid: false, error: 'No file selected' };
  if (!ALLOWED_IMAGE_TYPES.includes(file.type)) {
    return { valid: false, error: `${file.name}: use JPEG, PNG, or WebP` };
  }
  if (file.size > MAX_IMAGE_BYTES) {
    return { valid: false, error: `${file.name}: max size is 5 MB` };
  }
  return { valid: true };
}

export function validateImageFiles(files = []) {
  for (const file of files) {
    const result = validateImageFile(file);
    if (!result.valid) return result;
  }
  return { valid: true };
}

export function normalizeGalleryImages(images = []) {
  if (!Array.isArray(images)) return [];
  return images
    .filter((img) => img && img.url)
    .map((img, i) => ({
      url: img.url,
      path: img.path || null,
      isPrimary: !!img.isPrimary || (i === 0 && !images.some((x) => x.isPrimary)),
      alt: img.alt || null,
      role: img.role || null,
    }));
}

export function setPrimaryAt(images, index) {
  return images.map((img, i) => ({ ...img, isPrimary: i === index }));
}

export function removeImageAt(images, index) {
  const next = images.filter((_, i) => i !== index);
  if (next.length && !next.some((img) => img.isPrimary)) {
    next[0] = { ...next[0], isPrimary: true };
  }
  return next;
}

export function mergeUploadedImages(existing = [], uploaded = []) {
  const base = normalizeGalleryImages(existing);
  const hasPrimary = base.some((img) => img.isPrimary);
  const added = uploaded.map((u, i) => ({
    url: u.url,
    path: u.path,
    isPrimary: !hasPrimary && i === 0 && base.length === 0,
  }));
  return normalizeGalleryImages([...base, ...added]);
}

import { resolveMediaUrl } from '@/utils/helpers';

export function getImageAtIndex(images = [], index = 0) {
  const list = normalizeGalleryImages(images);
  if (!list.length) return '/placeholder.png';
  const safe = Math.min(Math.max(0, index), list.length - 1);
  return resolveMediaUrl(list[safe]?.url);
}
