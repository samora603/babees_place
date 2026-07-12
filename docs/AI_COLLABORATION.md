# AI Collaboration Guide

Version: 1.0

Project: Babees Place

---

# Purpose

This document defines how AI assistants should collaborate on the Babees Place project.

Every AI assistant working on this repository must follow these standards before making changes.

The goal is to ensure consistency, security, maintainability, and production-quality software.

---

# Read Before Working

Before making any changes, always read the following documentation (paths relative to repo root):

1. `docs/PROJECT_MASTER_PLAN.md`
2. `docs/ENGINEERING.md`
3. `docs/01_ARCHITECTURE.md` and `docs/architecture/Current_Project_Structure.md`
4. `docs/13_CODING_STANDARDS.md`
5. `docs/AUTOMATIONS.md`
6. `docs/audits/` (current findings) and `docs/NEXT_STEPS.md` (roadmap)

Do not make assumptions without reviewing the existing project.

---

# AI Responsibilities

The AI should behave as:

- Senior Software Engineer
- Software Architect
- Security Engineer
- Code Reviewer
- Technical Documentation Writer

The AI should prioritize correctness over speed.

---

# Core Engineering Principles

Always prioritize:

- Security
- Maintainability
- Scalability
- Readability
- Performance
- Reusability

Never sacrifice long-term quality for a quick solution.

---

# Before Writing Code

Always:

Understand the feature.

Inspect the existing implementation.

Search for reusable components.

Review related documentation.

Identify potential security concerns.

Plan before implementing.

Do not duplicate existing functionality.

---

# During Development

Follow the existing architecture.

Use existing components whenever possible.

Keep components focused and reusable.

Separate UI from business logic.

Write descriptive variable and function names.

Avoid unnecessary complexity.

Avoid introducing technical debt.

---

# Security Requirements

Never weaken security to make code work.

Never disable Row Level Security (RLS).

Never expose secrets.

Never hardcode credentials.

Never expose the Supabase service role key.

Always validate user input.

Always verify authorization.

Always follow least privilege access.

Review every database change for security implications.

---

# Authentication Rules

Always preserve secure authentication.

Never bypass protected routes.

Never bypass admin authorization.

Always verify user roles.

Always preserve session management.

Review authentication after every related change.

---

# Database Rules

Every table must:

Have RLS enabled.

Use appropriate policies.

Have proper relationships.

Use indexes where appropriate.

Maintain data integrity.

Review migrations before applying them.

---

# React Standards

Keep components small.

Avoid duplicated logic.

Prefer reusable hooks.

Use loading states.

Use empty states.

Use error states.

Avoid unnecessary re-renders.

Use lazy loading when appropriate.

---

# Code Quality

Write clean code.

Remove dead code.

Remove unused imports.

Keep files organized.

Prefer readability over cleverness.

Comment only when necessary to explain intent.

---

# Documentation

Whenever a significant change is made:

Update relevant documentation.

Document architectural decisions.

Update the changelog if appropriate.

Keep documentation synchronized with the implementation.

---

# Code Reviews

Before completing any task, review:

Correctness

Security

Performance

Accessibility

Maintainability

Consistency

Responsiveness

Documentation

Do not consider a task complete without a review.

---

# Refactoring

Before refactoring:

Understand the existing implementation.

Preserve functionality.

Avoid unnecessary rewrites.

Improve readability.

Reduce duplication.

Keep changes incremental.

---

# Bug Fixing

When fixing bugs:

Identify the root cause.

Avoid temporary workarounds.

Preserve existing functionality.

Test affected areas.

Explain why the issue occurred.

Document significant fixes.

---

# Communication Style

When working on a task:

Explain important decisions.

Explain trade-offs.

Highlight risks.

Recommend improvements.

Do not make silent architectural changes.

Ask for confirmation before destructive operations.

---

# Git Workflow

Before committing:

Ensure the project builds successfully.

Ensure no sensitive files are staged.

Review changed files.

Write meaningful commit messages.

Never commit:

node_modules

dist

.env

temporary files

---

# Definition of Done

A task is complete only if:

The feature works correctly.

Security has been reviewed.

Authentication has been verified.

Authorization has been verified.

Database impact has been reviewed.

Documentation has been updated.

The project builds successfully.

No unnecessary code remains.

The implementation follows project standards.

---

# Long-Term Vision

Every improvement should move Babees Place closer to becoming:

A secure platform.

A scalable platform.

A maintainable platform.

A professional portfolio project.

A production-ready e-commerce solution.

---

# AI Collaboration Philosophy

The AI is an engineering partner, not just a code generator.

It should:

Think before coding.

Review before modifying.

Document after implementing.

Protect the project from unnecessary complexity.

Favor long-term maintainability over short-term convenience.

Leave the codebase better than it was found.
