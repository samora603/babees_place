# 🛍️ Babees Place

> **A production-ready, secure, and scalable e-commerce platform built with React, Vite, Tailwind CSS, and Supabase.**

![Status](https://img.shields.io/badge/Status-Active%20Development-blue)
![Frontend](https://img.shields.io/badge/Frontend-React%20%2B%20Vite-61DAFB)
![Backend](https://img.shields.io/badge/Backend-Supabase-3ECF8E)
![Database](https://img.shields.io/badge/Database-PostgreSQL-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

# 📖 About

Babees Place is a modern e-commerce platform designed with a strong focus on:

- Security
- Scalability
- Performance
- Maintainability
- Excellent user experience

The project follows professional software engineering practices and is built using modern web technologies.

Unlike many tutorial projects, Babees Place is intended to be production-ready and continuously improved using documented engineering standards.

---

# 🎯 Project Goals

- Build a secure shopping platform.
- Provide an intuitive customer experience.
- Deliver a powerful admin dashboard.
- Maintain a scalable architecture.
- Follow production-level engineering practices.
- Document every major architectural decision.
- Use AI-assisted engineering responsibly.

---

# ✨ Features

## Customer

- User Authentication
- Product Browsing
- Product Search
- Product Categories
- Shopping Cart
- Wishlist
- Checkout
- Order History
- User Profile

---

## Admin

- Dashboard
- Product Management
- Category Management
- Order Management
- Customer Management
- Inventory Management
- Reports & Analytics

---

## Security

- Supabase Authentication
- Role-Based Authorization
- Row Level Security (RLS)
- Protected Routes
- Secure Storage
- Input Validation

---

# 🛠 Technology Stack

## Frontend

- React
- Vite
- Tailwind CSS
- React Router

---

## Backend

- Supabase
- PostgreSQL
- Authentication
- Storage
- Row Level Security
- Edge Functions (when required)

---

## Development Tools

- Cursor Pro
- Git
- GitHub
- VS Code (optional)
- npm

---

# 📁 Project Structure

```text
babees_place/
│
├── frontend/        # React + Vite application
│
├── supabase/        # migrations + config (Supabase backend)
│
├── docs/            # engineering docs, technical refs, audits, architecture
│
├── README.md
│
└── .gitignore
```

> Note: `.github/` (CI/CD) and `scripts/` are **planned for Phase 1** and do not yet exist.
> See `docs/architecture/Current_Project_Structure.md` for the full, current tree.

---

# 📚 Documentation

Project documentation is located inside:

```text
docs/
```

Key documents:

- `docs/00_PROJECT_VISION.md`, `docs/PROJECT_MASTER_PLAN.md` — vision & plan
- `docs/01_ARCHITECTURE.md`, `docs/architecture/Current_Project_Structure.md` — architecture
- `docs/ENGINEERING.md`, `docs/13_CODING_STANDARDS.md` — standards
- `docs/AI_COLLABORATION.md`, `docs/AUTOMATIONS.md`, `docs/DECISIONS.md` — process & ADRs
- `docs/03_Security.md`, `docs/technical/*` — security & technical references
- `docs/audits/*` — audit reports (project, security, frontend, database, supabase, performance, production readiness, Phase 0)
- `docs/NEXT_STEPS.md` — engineering roadmap

> Naming note: documentation uses the brand **"Babees Place"**, while some code artifacts still say **"Babis Place"** (e.g. `frontend/package.json` name, UI headings). This is a known inconsistency tracked in the Technical Debt Register; it is not yet reconciled to avoid rewriting working code during Phase 0.

---

# 🚀 Getting Started

## Clone Repository

```bash
git clone git@github.com:samora603/babees_place.git
```

---

## Install Dependencies

```bash
cd babees_place/frontend

npm install
```

---

## Environment Variables

Create:

```text
frontend/.env
```

Example:

```env
VITE_SUPABASE_URL=your-project-url

VITE_SUPABASE_ANON_KEY=your-anon-key
```

Never commit:

- .env
- Service Role Keys

---

## Run Development Server

```bash
npm run dev
```

---

## Production Build

```bash
npm run build
```

---

## Quality Scripts (Phase 1)

All commands run from `frontend/`:

```bash
npm run lint          # ESLint (config: .eslintrc.cjs) — must pass with 0 errors
npm run format        # Prettier write
npm run format:check  # Prettier check (used in review)
npm run test          # Vitest unit/component smoke tests
npm run test:watch    # Vitest watch mode
npm run test:e2e      # Playwright e2e (opt-in: needs `npx playwright install` + env)
```

CI runs `lint → test → build` on every push/PR via `.github/workflows/ci.yml`.

To enable the pre-commit hook (lint-staged) once per clone:

```bash
git config core.hooksPath .husky
```

---

# 🔐 Security Principles

This project follows a security-first philosophy.

Rules include:

- Never expose secrets.
- Never bypass authentication.
- Never disable Row Level Security.
- Validate all user input.
- Follow least-privilege access.

Every database table must use RLS.

---

# 🏗 Engineering Standards

Development follows documented engineering standards.

Before implementing features:

- Read documentation.
- Review architecture.
- Follow coding standards.
- Update documentation.
- Perform security review.

---

# 🤖 AI-Assisted Development

This project is designed for collaboration with AI engineering assistants.

AI must:

- Read project documentation before coding.
- Preserve security.
- Explain architectural changes.
- Update documentation.
- Avoid unnecessary complexity.

AI should never weaken security to make code work.

---

# 📋 Development Workflow

Every feature follows the same lifecycle.

```text
Plan

↓

Review Existing Code

↓

Implement

↓

Review

↓

Test

↓

Document

↓

Commit

↓

Push
```

---

# 🧪 Testing

Before every release verify:

- Authentication
- Authorization
- Product Management
- Shopping Cart
- Checkout
- Orders
- Admin Dashboard
- Database Security
- Storage Access

---

# 🚀 Deployment

Before deployment ensure:

- Production build passes.
- Environment variables are configured.
- Database migrations are applied.
- RLS policies are verified.
- Storage permissions are reviewed.
- Documentation is up to date.

---

# 📈 Roadmap

Current development focuses on:

- Authentication
- Product Management
- Shopping Experience
- Orders
- Payments
- Admin Dashboard
- Production Readiness

Future improvements:

- AI Recommendations
- Mobile Application
- Multi-Vendor Support
- Analytics
- Customer Loyalty
- International Payments

---

# 🤝 Contributing

Contributions should follow the project's engineering documentation.

Before submitting changes:

- Follow coding standards.
- Review security.
- Update documentation.
- Test thoroughly.

---

# 📄 License

This project is licensed under the MIT License.

---

# 👨‍💻 Project Owner

**Edwin Samora**

Software Engineer | AI Developer | Technology Entrepreneur

GitHub:

https://github.com/samora603

---

# ⭐ Philosophy

> Build software that is secure, maintainable, scalable, and ready for production.

Every commit should leave the project better than it was before.
