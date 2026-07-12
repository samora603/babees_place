# Cursor AI Automations

These are standard workflows for every engineering task.

---

## Automation 1 — Feature Development

When implementing a feature:

1. Understand the requirement.
2. Inspect the existing architecture.
3. Reuse existing components where possible.
4. Write clean code.
5. Add loading and error states.
6. Review security implications.
7. Update documentation.

---

## Automation 2 — Authentication Review

Whenever authentication code changes:

Review:

- Login
- Logout
- Session management
- Route protection
- Admin authorization
- Role detection

Ensure no protected routes are publicly accessible.

---

## Automation 3 — Supabase Review

Whenever SQL, migrations, or database code changes:

Review:

- RLS
- Indexes
- Foreign Keys
- Constraints
- Policies
- Security

Never leave a table without RLS.

---

## Automation 4 — React Review

Whenever React files change:

Check:

- Component size
- useEffect dependencies
- State management
- Loading states
- Error handling
- Accessibility
- Performance

---

## Automation 5 — Security Audit

Before every commit:

Review:

Authentication

Authorization

Secrets

Environment variables

Input validation

Output sanitization

Data exposure

Storage permissions

---

## Automation 6 — Documentation

After every completed feature:

Update:

Engineering documentation

API documentation

Database documentation

Feature documentation

---

## Automation 7 — Git Review

Before every commit:

Run build.

Review changed files.

Remove dead code.

Remove unused imports.

Write a meaningful commit message.

---

## Automation 8 — Production Readiness

Before deployment:

Review:

Security

Performance

Accessibility

Responsive design

Database

Storage

Authentication

Authorization

Error handling

Logging

---

## Automation 9 — Code Review

Every completed task should be reviewed for:

Maintainability

Readability

Performance

Security

Scalability

Consistency

---

## Automation 10 — Final Approval

Before marking any task complete:

Confirm:

✓ Feature works.

✓ No security issues introduced.

✓ Documentation updated.

✓ Project builds successfully.

✓ Code follows engineering standards.
