# Phase 1.7A — Repository Baseline Adoption Report

**Date:** 2026-07-12
**Scope:** Repository only. **No live database changes. No migrations executed. No frontend changes.**
**Result:** ✅ Baseline established; historical migrations preserved; repository ready for authoring forward migrations (pending the manual steps in §7).

---

## 1. Executive Summary

The verified read-only baseline from Phase 1.6 Workstream A
(`docs/database/generated_baseline/001_initial_schema.sql`) has been adopted as the official
initial migration at `supabase/migrations/001_initial_schema.sql`. The three fictional/
superseded migrations and one empty placeholder were moved (not deleted) into
`supabase/migrations/archive/` with a `README.md` explaining each. Documentation was updated
to reference the new baseline (`docs/database/Migration_History.md` created; this report added).

The migration directory now contains a single, coherent, authoritative baseline that matches
the live schema. No migration in the active sequence depends on fictional schema objects.

---

## 2. Baseline verification (pre-adoption)

Re-confirmed against `Baseline_Migration_Verification.md` and by reading the file directly:

- 7 tables: `cart_items`, `categories`, `order_items`, `orders`, `products`, `profiles`, `wishlists`.
- 1 enum: `public.order_status` (defined; `orders.status` is `text`).
- 7 PKs (incl. composite `products (id, name)`), 2 FKs (`order_items.order_id`→orders CASCADE, `profiles.id`→auth.users CASCADE).
- RLS enabled on all 7 tables; 10 policies present; `cart_items`/`categories`/`wishlists` deny-all.
- 0 functions, 0 triggers, 0 non-PK indexes (matches live — nothing lost).

The file is a faithful `pg_dump` of the live `public` schema and complete.

---

## 3. Actions taken

| # | Action | Command / Method | Reversible? |
|---|---|---|---|
| 1 | Created archive directory | `mkdir -p supabase/migrations/archive` | Yes |
| 2 | Archived fictional `001` | `git mv 001_schema_rls_place_order.sql archive/` | Yes |
| 3 | Archived empty placeholder | `git mv 20260617042152_remote_schema.sql archive/` | Yes |
| 4 | Archived `002` (deprecated) | `mv 002_phase1_security_hardening.sql archive/` | Yes |
| 5 | Archived `003` (deprecated) | `mv 003_phase1_indexes_constraints.sql archive/` | Yes |
| 6 | Promoted baseline | `cp generated_baseline/001_initial_schema.sql supabase/migrations/001_initial_schema.sql` | Yes |
| 7 | Added provenance header | comment-only edit to the promoted file (DDL unchanged) | Yes |
| 8 | Documented archive | created `supabase/migrations/archive/README.md` | Yes |
| 9 | Recorded history | created `docs/database/Migration_History.md` | Yes |

**Preservation guarantee:** nothing was deleted. The pristine artifact remains at
`docs/database/generated_baseline/001_initial_schema.sql`; all superseded files remain in
`supabase/migrations/archive/`.

**Only modification to schema content:** a comment header was prepended to the promoted
baseline. The DDL is byte-identical to the generated artifact.

---

## 4. Archived files (classification)

| File (now under `archive/`) | Classification | Reason |
|---|---|---|
| `001_schema_rls_place_order.sql` | Deprecated (fictional) | Never applied; diverges from live (tables/columns/PK/functions) |
| `002_phase1_security_hardening.sql` | Deprecated | Forward-fix against fictional `001`; `DO NOT APPLY AS-IS` |
| `003_phase1_indexes_constraints.sql` | Deprecated | Forward-fix against fictional `001`; references non-existent objects |
| `20260617042152_remote_schema.sql` | Archived (empty) | 0-byte placeholder from an earlier empty pull |

Intent of `002`/`003` is preserved as planned migrations `M2`/`M3`/`M5` in `Migration_Strategy.md`.

---

## 5. Active migration sequence (post-adoption)

```
supabase/migrations/
├── 001_initial_schema.sql        ← ACTIVE baseline (authoritative, matches live)
└── archive/                      ← historical only, never applied
    ├── README.md
    ├── 001_schema_rls_place_order.sql
    ├── 002_phase1_security_hardening.sql
    ├── 003_phase1_indexes_constraints.sql
    └── 20260617042152_remote_schema.sql
```

Sequence is coherent: exactly one active migration, consistently named, no duplicate versions,
no dependency on fictional objects.

---

## 6. Repository verification

- [x] Migration directory has a coherent sequence (single active baseline).
- [x] Filenames consistent (`001_initial_schema.sql`; archived files clearly separated).
- [x] Documentation references the new baseline (`Migration_History.md`, this report, header in the SQL).
- [x] No active migration depends on fictional schema objects (fictional files archived).
- [x] Pristine generated artifact retained and unmodified.

---

## 7. Remaining work before forward migrations can be authored

1. **Adopt baseline on live** (reconciliation — NOT part of 1.7A): `supabase migration repair
   --status applied 001`, then confirm `supabase db diff --linked` is clean (Runbook §1 Stage 2 / `M0`).
2. Run the four read-only data verifications (product `id` uniqueness, cart/wishlist duplicate
   rows, storage `products` bucket, distinct `profiles.role` values).
3. Obtain approvals for the destructive/normalizing migrations (`M5`/`M6`/`M7`).
4. Author `M1..M8` as new timestamped migrations against the baseline.

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Live history still empty until `migration repair` is run | Med | Documented as the first reconciliation step (§7.1); `db push` must not run before repair |
| Numeric `001_` prefix vs timestamped forward migrations | Low | Documented naming convention; `001_` sorts first, forward migrations use timestamps |
| Someone applies an archived file by mistake | Low | `archive/README.md` + headers say DO NOT APPLY; files outside the active path |
| Baseline carries live imperfections (composite PK, bad defaults) | Med | Intended (faithful mirror); cleanups are gated forward migrations `M6`/`M7` |

---

## 9. Manual review items

- Confirm the `001_` numeric prefix is acceptable, or re-version to a timestamp before first
  `db push` (either is fine; docs assume `001_`).
- Human to run `migration repair` on live at reconciliation time (needs project credentials).
- Confirm no additional objects in non-`public` schemas are relied upon (none observed).

---

## Final Validation

- ✅ Repository baseline established (`supabase/migrations/001_initial_schema.sql`).
- ✅ Historical migrations preserved (moved to `archive/`, nothing deleted; pristine artifact retained).
- ✅ Repository ready for authoring canonical forward migrations (after §7 manual steps).
- ✅ No live database changes were made.
- ✅ No frontend changes were made.

**Stop:** Phase 1.7A complete.
