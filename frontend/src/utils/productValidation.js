import { isValidSlug } from '@/utils/slug';

export function validateProductForm(form) {
  const errors = {};

  if (!form.name?.trim()) errors.name = 'Name is required';

  if (!form.description?.trim()) errors.description = 'Description is required';

  const price = Number(form.price);
  if (form.price === '' || Number.isNaN(price) || price < 0) {
    errors.price = 'Price must be a non-negative number';
  }

  const stock = Number(form.stock);
  if (form.stock === '' || Number.isNaN(stock) || stock < 0) {
    errors.stock = 'Stock must be a non-negative number';
  }

  if (form.discountPrice !== '' && form.discountPrice != null) {
    const discount = Number(form.discountPrice);
    if (Number.isNaN(discount) || discount < 0) {
      errors.discountPrice = 'Discount must be non-negative';
    } else if (!Number.isNaN(price) && discount > price) {
      errors.discountPrice = 'Discount cannot exceed price';
    }
  }

  if (form.slug && !isValidSlug(form.slug)) {
    errors.slug = 'Slug may only contain lowercase letters, numbers, and hyphens';
  }

  return { valid: Object.keys(errors).length === 0, errors };
}

export function validateCategoryForm(form) {
  const errors = {};
  if (!form.name?.trim()) errors.name = 'Name is required';
  if (form.slug && !isValidSlug(form.slug)) {
    errors.slug = 'Slug may only contain lowercase letters, numbers, and hyphens';
  }
  return { valid: Object.keys(errors).length === 0, errors };
}
