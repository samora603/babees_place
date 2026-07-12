# Archived migrations (historical reference — DO NOT APPLY)

These files are preserved for history only. They are **not** part of the active
migration sequence and must **not** be applied to any database. The active baseline
is `supabase/migrations/001_initial_schema.sql`. See
`docs/database/Migration_History.md` for the full classification.

| File | Classification | Why archived |
|---|---|---|
| `001_schema_rls_place_order.sql` | Deprecated (fictional) | Describes a schema that was never applied to live (tables `cart`/`wishlist`, `orders.total_amount`, `profiles.full_name`, `products.stock`, functions `place_order`/`is_admin`/`handle_new_user`). Superseded by the live baseline. |
| `002_phase1_security_hardening.sql` | Deprecated | Forward-fix written against the fictional `001`; targets objects/columns absent on live. Already carries a `DO NOT APPLY AS-IS` header. Will be re-authored against the baseline during reconciliation. |
| `003_phase1_indexes_constraints.sql` | Deprecated | Forward-fix against the fictional `001` (references `cart`, `orders.payment_status`, `profiles.updated_at` — none exist on live). Re-authored during reconciliation. |
| `20260617042152_remote_schema.sql` | Deprecated (empty placeholder) | 0-byte artifact of an earlier empty `db pull`. Replaced by the populated baseline. |

The intent of `002`/`003` (security hardening, indexes/constraints) is not lost — it
is carried forward as the planned migrations `M3/M2` and `M5` in
`docs/database/Migration_Strategy.md`, to be authored against the real baseline.
