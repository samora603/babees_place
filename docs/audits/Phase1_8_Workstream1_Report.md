# Phase 1.8 — Workstream 1: Live Database Preparation & Migration History Repair

**Date:** 2026-07-12
**Author:** Engineering (AI-assisted)
**Scope:** First workstream to interact with the linked Supabase project. Prepare live for
migrations by repairing migration history to record the baseline `001` as applied.
**Strictly excluded:** executing `002–010`, frontend/backend changes, authoring migrations,
any repair beyond history, and any Workstream 2 task.

---

## 1. Executive summary

The linked Supabase project was verified, the repository baseline (`001_initial_schema.sql`)
was confirmed **byte-identical to the current live `public` schema**, and the remote migration
history was confirmed **empty**. On that basis, the single authorized operation —
`supabase migration repair --status applied 001` — was executed. It recorded `001` as applied
**without changing the live schema**: a fresh dump taken after the repair is byte-identical to
the dump taken before it. No forward migrations (`002–010`) were applied; they remain pending.

**Result: SUCCESS. GO for Phase 1.8 Workstream 2** (subject to the documented pre-checks,
approvals, and backups for the gated migrations).

| Criterion | Status |
|---|---|
| Live schema unchanged | ✅ pre==post dump (byte-identical) |
| Migration history repaired | ✅ `[001] => applied` |
| Baseline recognized | ✅ `001` present in Remote column |
| Repository unchanged (code/migrations) | ✅ only this report added |
| Frontend untouched | ✅ |
| No forward migrations executed | ✅ `002–010` Remote column blank |
| Ready for Workstream 2 | ✅ (gated) |

---

## 2. Environment

| Item | Value |
|---|---|
| Supabase CLI | `2.106.0` (newer `2.109.1` available — informational) |
| Project ref | `qfcygrxrfszcdltangec` |
| Project name | `Babis-place` |
| Organization | `skkcjbcqsfmrksbvzeiq` |
| Postgres major | `17.6.1.127` |
| OS / shell | Linux / zsh |
| Auth | CLI session reached remote successfully; no `SUPABASE_*` env vars present (cached login used) |

---

## 3. Git verification (Step 1)

| Check | Value |
|---|---|
| Branch | `phase-1.7-reconciliation` |
| Tag at HEAD | `v0.3.1-phase-1.7b-complete` |
| HEAD commit | `fc08a37 feat(frontend): reconcile application with canonical database schema` |
| Working tree | **clean** (no modified/untracked before this report) |

---

## 4. Supabase & migration directory verification (Steps 1–2)

`supabase/migrations/` contents:

```
001_initial_schema.sql
002_additive_columns.sql
003_functions_and_triggers.sql
004_rls_and_security.sql
005_integrity_constraints.sql
006_storage_policies.sql
007_data_normalization.sql
008_structural_reconciliation.sql
009_product_integrity.sql
010_performance_optimizations.sql
archive/
  ├─ 001_schema_rls_place_order.sql      (deprecated / fictional)
  ├─ 002_phase1_security_hardening.sql   (deprecated)
  ├─ 003_phase1_indexes_constraints.sql  (deprecated)
  ├─ 20260617042152_remote_schema.sql    (0-byte placeholder)
  └─ README.md
```

✅ `001`–`010` present; `archive/` present. Linked project matches the repository (`project-ref`
= `qfcygrxrfszcdltangec`).

---

## 5. Baseline verification (Step 3) — read-only schema comparison

A read-only dump of the live `public` schema was compared against the pristine baseline
artifact.

- Command: `supabase db dump --linked -s public -f /tmp/pre_repair_live.sql` (read-only).
- Comparison: `diff docs/database/generated_baseline/001_initial_schema.sql /tmp/pre_repair_live.sql`
- **Result: EXIT 0 — no differences. The baseline is byte-identical to the live schema.**

(A secondary diff of `supabase/migrations/001_initial_schema.sql` minus its 21-line provenance
header showed only 2 leading blank lines — a cosmetic artifact of the header strip; the DDL is
identical. The authoritative comparison is the pristine artifact above.)

➡️ **Precondition met — proceed to repair.** (Had any schema difference existed, the process
would have STOPPED here without repairing.)

---

## 6. Migration history BEFORE repair (Step 4)

`supabase migration list --linked`:

```
 Local | Remote | Time (UTC)
-------|--------|------------
 001   |        | 001
 002   |        | 002
 ...   |        | ...
 010   |        | 010
```

✅ **Remote column empty for every migration → migration history is empty; `001` is NOT
recorded.**

---

## 7. Exact repair performed (Step 5)

```bash
supabase migration repair --status applied 001 --linked
```

Output:

```
Initialising login role...
Connecting to remote database...
Repaired migration history: [001] => applied
Finished supabase migration repair.
```

Exit code: `0`. Only `001` was repaired. No later migration was touched. This writes a single
row to the remote `supabase_migrations.schema_migrations` table (version `001`, marked applied);
it does **not** execute the `001` DDL and does **not** alter the schema.

---

## 8. Migration history AFTER repair (Step 6)

`supabase migration list --linked`:

```
 Local | Remote | Time (UTC)
-------|--------|------------
 001   | 001    | 001
 002   |        | 002
 003   |        | 003
 004   |        | 004
 005   |        | 005
 006   |        | 006
 007   |        | 007
 008   |        | 008
 009   |        | 009
 010   |        | 010
```

✅ **Remote history now contains `001` and nothing else.** `002–010` remain unapplied (blank
Remote), exactly as intended.

---

## 9. Schema verification (Step 7)

Because only `001` was repaired (and `002–010` are intentionally unapplied), `supabase db diff
--linked` would report the nine pending forward migrations — which is **expected and not a
schema change caused by the repair**. Therefore the precise, correct verification that the
repair left the schema untouched is a **before/after live dump comparison**:

- `supabase db dump --linked -s public -f /tmp/post_repair_live.sql` (read-only)
- `diff /tmp/pre_repair_live.sql /tmp/post_repair_live.sql` → **EXIT 0 (no changes)**
- `diff docs/database/generated_baseline/001_initial_schema.sql /tmp/post_repair_live.sql` → **EXIT 0 (byte-identical)**

✅ **The live schema is unchanged by the repair.** No differences to report; nothing to fix.

---

## 10. Risks

| Risk | Severity | Mitigation / Note |
|---|---|---|
| Repair marks `001` applied without running it | — | **Correct by design** — the live schema already equals `001` (verified byte-identical in §5). This is the intended reconciliation. |
| History repair is a remote write | Low | Reversible: `supabase migration repair --status reverted 001` (or remove the row). Schema untouched (§9). |
| CLI `2.106.0` behind `2.109.1` | Info | No functional impact for `migration list/repair/db dump`. Optional upgrade later. |
| Forward migrations `002–010` now "pending" against a repaired history | Expected | Applying them is **Workstream 2**; gated `007`/`008` require backup + approval + window. |
| No `SUPABASE_*` env; relies on cached CLI login | Low | Session worked for all remote ops; ensure credentials remain available for WS2. |

---

## 11. Remaining prerequisites (before Workstream 2)

1. Read-only pre-checks on live (gate the high-risk migrations):
   - `SELECT id, count(*) FROM products GROUP BY id HAVING count(*)>1;` (gates `008` PK change)
   - duplicate `(user_id, product_id)` scan on `cart_items`/`wishlists` (gates `007`/`009`)
   - `products` storage bucket existence + visibility (gates `006` behavior)
   - distinct `orders.status` and `profiles.role` values (gates `007` CHECKs / VALIDATE)
2. **Resolve F-1** (`orders → profiles` PostgREST embed has no supporting FK — see
   `Phase1_7B_Final_Validation.md` §6) as a design decision before/with WS2.
3. Fresh backup (dump + PITR) and explicit approval + maintenance window for `007` (M6) and
   `008` (M7).
4. Apply on staging first (or a branch), run post-apply `VALIDATE CONSTRAINT` and smoke tests,
   then production per the Runbook order.

---

## 12. Evidence (key results)

| Evidence | Result |
|---|---|
| Baseline artifact vs live dump (pre) | `diff` exit **0** — identical |
| Remote history (before) | empty (all Remote blank) |
| Repair output | `Repaired migration history: [001] => applied` (exit 0) |
| Remote history (after) | `001` recorded; `002–010` blank |
| Live dump pre vs post repair | `diff` exit **0** — schema unchanged |
| Baseline artifact vs live dump (post) | `diff` exit **0** — identical |
| Git working tree | clean (only this report added afterward) |

---

## 13. Commands executed (exact, in order)

Read-only verification:
```bash
git branch --show-current
git describe --tags ; git tag --points-at HEAD ; git status --short ; git log -1 --oneline
supabase --version
cat supabase/.temp/project-ref ; cat supabase/.temp/linked-project.json ; cat supabase/.temp/postgres-version
ls -la supabase/migrations/archive/
supabase migration list --linked                                   # history BEFORE (empty)
supabase db dump --linked -s public -f /tmp/pre_repair_live.sql    # read-only
diff docs/database/generated_baseline/001_initial_schema.sql /tmp/pre_repair_live.sql   # exit 0
```

Authorized write (single):
```bash
supabase migration repair --status applied 001 --linked            # [001] => applied
```

Post-repair verification (read-only):
```bash
supabase migration list --linked                                   # history AFTER (001 only)
supabase db dump --linked -s public -f /tmp/post_repair_live.sql   # read-only
diff /tmp/pre_repair_live.sql /tmp/post_repair_live.sql            # exit 0 (schema unchanged)
diff docs/database/generated_baseline/001_initial_schema.sql /tmp/post_repair_live.sql  # exit 0
```

(`< /dev/null` was appended to Supabase commands to guarantee non-interactive execution.)

---

## 14. Go / No-Go

**GO.** Live preparation is complete and verified. Migration history records the baseline
`001` as applied; the live schema is provably unchanged; the repository, frontend, and backend
logic are untouched; no forward migration was executed. The project is ready for **Phase 1.8
Workstream 2** (forward migration application), gated on the pre-checks, F-1 resolution,
approvals, and backups in §11.

---

## Final validation

- ✅ live schema unchanged (pre/post dumps byte-identical)
- ✅ migration history repaired (`001` recorded)
- ✅ baseline recognized (`001` in Remote)
- ✅ repository unchanged (no code/migration edits; only this report added)
- ✅ frontend untouched
- ✅ no forward migrations executed (`002–010` pending)
- ✅ ready for Workstream 2

**STOP — awaiting explicit approval before Workstream 2. No further action taken automatically.**
