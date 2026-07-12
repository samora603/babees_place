# ADR-001: Live Database Reconciliation Strategy

- **Status:** Proposed (awaiting human approval to execute)
- **Date:** 2026-07-12
- **Deciders:** Lead Architect / Principal DB Engineer (proposal); project owner (approval)
- **Related:** `docs/database/Schema_Comparison_Matrix.md`, `Canonical_Schema_Proposal.md`,
  `Migration_Strategy.md`, `docs/audits/Frontend_Database_Compatibility.md`,
  `docs/audits/Phase1_Final_Closure_Report.md`

---

## Context

Phase 1 live verification (read-only `supabase db dump`) proved the repository and the
live Supabase project (`qfcygrxrfszcdltangec`) have **diverged fundamentally**:

- The live database was built **manually**; its migration history is **empty**.
- Repo migration `001` describes an **idealized schema that was never applied**.
- The live schema differs in table names (`cart_items`/`wishlists`), columns
  (`orders.total` vs `total_amount`; missing `profiles.full_name`, `products.stock`,
  `discount_price`, image fields; missing `orders.payment_status`), a **composite PK**
  on `products (id, name)`, and **missing functions** (`place_order`, `is_admin`,
  `handle_new_user`).
- Several live tables have **RLS enabled but no policies** (`cart_items`, `wishlists`,
  `categories`) → deny-all.
- A **Critical** live vulnerability persists: `profiles` UPDATE policy has no `WITH CHECK`
  (role self-escalation).
- Tables referenced only in code (`payments`, `pickup_locations`, `addresses`) **do not exist**.

Phase 1 Phase-1-stabilization migrations `002`/`003` are therefore **not applicable to live**.

## Problem

The repository and the live database are two different systems of record with no shared
migration history. This blocks Phase 2 because:

1. Core commerce flows (cart, wishlist, checkout, admin, inventory) are broken against the
   live schema (wrong table names, missing columns, missing `place_order` RPC).
2. A Critical security vulnerability (role self-escalation) is live.
3. There is no safe, repeatable way to evolve the schema (no baseline, manual-only history).

We must converge them **without losing live data** and **without guessing** at objects for
which we have no evidence — while a stabilization mandate forbids new features and
destructive operations without explicit approval.

## Decision

Adopt the **live database as the source of truth** and reconcile via an
**additive, non-destructive-first** migration sequence, pairing DB changes with the
matching frontend changes. Specifically:

1. **Capture a real baseline** with `supabase db pull`; retire the fictional `001` and the
   empty `20260617042152_remote_schema.sql`.
2. **Prefer code changes over destructive DB changes** for pure naming mismatches
   (`.from('cart')`→`cart_items`, `wishlist`→`wishlists`, `total_amount`→`total`).
3. **Add** missing columns/tables/functions/policies the application genuinely requires
   (see `Migration_Strategy.md` M1–M5, M8).
4. **Gate destructive/normalizing changes** (products PK `(id,name)`→`(id)`, `"Description"`
   rename, role normalization, UNIQUE constraints) behind explicit approval, verified
   preconditions, a backup, and a maintenance window (M6–M7).
5. **Defer feature-shaped gaps** (`payments`, `pickup_locations`, `addresses`) out of
   stabilization; guard/disable those code paths until designed.
6. **Keep the stricter live posture** where safer (e.g., `order_items` INSERT blocked;
   order creation only via `place_order`).

No migrations are generated or applied under this ADR until approved.

## Alternatives considered

- **A. Reshape live to match repo `001` (destructive rebuild).** Rejected: risks data loss,
  large blast radius, and treats the fictional `001` as canonical despite live being the
  real system of record. Only viable if live data is disposable (not established).
- **B. Rewrite all frontend code to match live exactly, add nothing.** Rejected: live lacks
  columns/functions the product needs (`stock`, `full_name`, checkout RPC), so pure code
  adaptation cannot deliver core commerce.
- **C. Continue without reconciliation.** Rejected: checkout/cart/wishlist/admin are broken
  against live and a Critical vuln remains open.
- **D. Point the app at a fresh, migration-defined database.** Rejected for now: discards
  existing live data/config; could be reconsidered if live data proves throwaway.

Chosen: a hybrid (adopt live + additive reconciliation) = lowest risk that still yields a
working, secure schema.

## Trade-offs

| Dimension | Chosen (adopt live + additive) | Cost accepted |
|---|---|---|
| Data safety | High — additive, backups gate destructive steps | Slower than a rebuild |
| Delivery speed | Medium — many small coordinated PRs | Not a single big-bang change |
| Code churn | Adapt frontend to live names (`cart_items`, `wishlists`, `total`) | Touches services/contexts |
| Schema cleanliness | Good end state (snake_case, FTS, FKs) | Some anomalies (`(id,name)` PK) only fixed in gated M7 |
| Security | Critical fix ships early (M3) | Storage/auth remain manual/dashboard items |
| Reversibility | Additive steps reverse via `DROP`; risky steps via backup restore | M6/M7 need a maintenance window |

## Consequences

**Positive**
- Non-destructive default → minimal risk to live data.
- Each step is independently reversible (additive) or backup-protected (destructive).
- Closes the Critical role-escalation gap early (M3, live-compatible).
- Produces a real, version-controlled baseline and a repeatable migration history.

**Negative / costs**
- Requires coordinated DB + frontend changes (several PRs).
- Some approval-gated steps (PK change, normalization) need a maintenance window.
- Interim period where code and live are partially aligned — must ship per-area to avoid
  regressions.

**Neutral**
- Canonical naming becomes snake_case (`discount_price`), and role vocabulary standardizes
  on `('customer','admin')` (adopting the live default over repo `'user'`).

## Future migration policy

- **Migrations are the only way schema changes reach any environment.** No more manual SQL
  in the dashboard for schema/policy changes.
- Every change: `supabase migration new` → review → apply to **staging** → `db diff` clean →
  apply to prod, always after `supabase db dump` backup.
- `main` CI should (future) run `supabase db diff` to detect drift.
- Destructive changes require an ADR update or a linked approval note and a backup reference.
- Keep `Schema_Comparison_Matrix.md` updated until live == repo (`db diff` returns no changes).
