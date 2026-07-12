import { describe, it, expect } from 'vitest';
import { validateProductForm, validateCategoryForm } from './productValidation';

describe('validateProductForm', () => {
  const valid = {
    name: 'Guitar',
    description: 'A nice guitar',
    price: '1000',
    stock: '5',
    discountPrice: '',
    slug: 'guitar',
  };

  it('passes a valid form', () => {
    expect(validateProductForm(valid).valid).toBe(true);
  });

  it('requires name and description', () => {
    const result = validateProductForm({ ...valid, name: '', description: '' });
    expect(result.valid).toBe(false);
    expect(result.errors.name).toBeTruthy();
    expect(result.errors.description).toBeTruthy();
  });

  it('rejects negative price', () => {
    const result = validateProductForm({ ...valid, price: '-1' });
    expect(result.valid).toBe(false);
    expect(result.errors.price).toBeTruthy();
  });

  it('rejects discount greater than price', () => {
    const result = validateProductForm({ ...valid, price: '100', discountPrice: '150' });
    expect(result.valid).toBe(false);
    expect(result.errors.discountPrice).toBeTruthy();
  });

  it('rejects invalid slug format', () => {
    const result = validateProductForm({ ...valid, slug: 'Bad Slug!' });
    expect(result.valid).toBe(false);
    expect(result.errors.slug).toBeTruthy();
  });
});

describe('validateCategoryForm', () => {
  it('requires category name', () => {
    const result = validateCategoryForm({ name: '', slug: '' });
    expect(result.valid).toBe(false);
    expect(result.errors.name).toBeTruthy();
  });

  it('passes valid category', () => {
    expect(validateCategoryForm({ name: 'Instruments', slug: 'instruments' }).valid).toBe(true);
  });
});
