# Babees Place Engineering Standards

## Project Vision

Babees Place is a production-grade e-commerce platform built with React, Vite, Tailwind CSS, and Supabase.

Every change should prioritize:

- Security
- Scalability
- Maintainability
- Performance
- Readability
- Production readiness

Working code is not enough. Code must also be secure, clean, and maintainable.

---

# Architecture

Frontend

- React
- Vite
- Tailwind CSS
- React Router

Backend

- Supabase
- PostgreSQL
- Authentication
- Row Level Security (RLS)
- Storage
- Edge Functions (when required)

---

# Folder Structure

frontend/

- src/
- components/
- pages/
- layouts/
- context/
- hooks/
- services/
- lib/
- utils/
- assets/

supabase/

- migrations/   (present — but incomplete; see docs/technical/02_Database.md)
- config.toml   (present)
- functions/    (planned — no Edge Functions exist yet)
- seed.sql      (planned — referenced in config.toml but not present)

docs/

Engineering documentation (see docs/architecture/Current_Project_Structure.md for the current tree)

---

# Security Standards

Every database table must:

- Have RLS enabled.
- Follow least-privilege access.
- Never expose sensitive data publicly.
- Validate ownership before updates or deletes.

Never bypass RLS.

Never expose service role keys in frontend code.

Never hardcode secrets.

Always validate user input.

Always sanitize data before rendering.

---

# Authentication

Use Supabase Authentication.

Customers:

- Access customer pages only.

Admins:

- Access admin dashboard only.

Protect every route.

Never rely only on frontend checks.

---

# Database Standards

Every table should include:

- Primary key
- Foreign keys
- Indexes where appropriate
- Constraints
- Timestamps
- Appropriate RLS policies

Review indexes before production.

---

# React Standards

Keep components small.

Prefer reusable components.

Separate business logic from UI.

Avoid unnecessary re-renders.

Always include:

- Loading state
- Empty state
- Error state

---

# Code Quality

Use descriptive names.

Avoid duplicated code.

Remove unused imports.

Avoid large files.

Prefer composition over repetition.

---

# Git Standards

Small commits.

Clear commit messages.

Never commit:

- node_modules
- dist
- .env

Commit only tested code.

---

# Documentation

Whenever a major feature is completed:

Update documentation.

Document architectural decisions.

Document breaking changes.

---

# Performance

Lazy-load routes where appropriate.

Optimize images.

Minimize unnecessary renders.

Review expensive database queries.

---

# Testing

Test every major feature before committing.

Verify:

Authentication

Authorization

Checkout

Cart

Orders

Payments

Admin Dashboard

---

# Deployment

Before deployment:

No console errors.

No TypeScript errors.

No lint errors.

No exposed secrets.

No missing environment variables.

Review RLS policies.

Run production build successfully.

---

# Engineering Principle

Never optimize for speed at the expense of security or maintainability.

Every change should leave the project in a better state than it was before.
