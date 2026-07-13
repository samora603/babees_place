# Phase 2 Workstream 4 — Milestone 4.2 Implementation Report

**Operational Dashboard Widgets**  
Date: 2026-07-13  
Status: Complete

---

## Features implemented

| Feature | Status |
|---|---|
| `analyticsService.getRecentOrders(limit)` | ✅ |
| `analyticsService.getLowStockProducts()` | ✅ |
| `analyticsService.getDashboardActivity(limit)` | ✅ |
| Recent Orders widget (10 rows, badges, navigation) | ✅ |
| Low Stock widget (severity levels, sorted by stock) | ✅ |
| Recent Activity widget (15 events from `order_events`) | ✅ |
| Admin dashboard layout (KPIs + 2-column + activity) | ✅ |
| Parallel dashboard fetch | ✅ |
| Per-widget loading / empty / error states | ✅ |
| Tests + documentation | ✅ |

---

## Files changed

### New

| File | Purpose |
|---|---|
| `frontend/src/components/admin/dashboard/RecentOrdersWidget.jsx` | Recent orders table widget |
| `frontend/src/components/admin/dashboard/LowStockWidget.jsx` | Low stock table widget |
| `frontend/src/components/admin/dashboard/RecentActivityWidget.jsx` | Activity feed widget |
| `frontend/src/components/admin/dashboard/DashboardWidgetCard.jsx` | Shared widget card shell |
| `frontend/src/components/admin/dashboard/DashboardWidgetSkeleton.jsx` | Skeleton loader |
| `frontend/src/components/admin/dashboard/DashboardWidgetEmpty.jsx` | Empty state |
| `frontend/src/components/admin/dashboard/DashboardWidgetError.jsx` | Error state + retry |
| `frontend/src/components/admin/dashboard/FulfillmentBadge.jsx` | Pickup/delivery badge |
| `frontend/src/components/admin/dashboard/*.test.jsx` | Widget tests (3 files) |
| `docs/audits/Phase2_WS4_Milestone4.2_Report.md` | This report |

### Modified

| File | Change |
|---|---|
| `frontend/src/services/analyticsService.js` | Added three widget data methods |
| `frontend/src/services/analyticsService.test.js` | Tests for new methods |
| `frontend/src/models/dashboard.js` | Widget types, mappers, event/stock helpers |
| `frontend/src/models/dashboard.test.js` | Tests for new helpers |
| `frontend/src/pages/admin/AdminDashboard.jsx` | Parallel fetch + widget layout |
| `docs/technical/11_Analytics.md` | Widget architecture + data flow |

---

## Architecture decisions

1. **Extend 4.1, do not replace** — `getDashboardSnapshot()` and KPI components are unchanged. Widgets are additive.

2. **Business logic in models + service** — Supabase queries and row mapping live in `analyticsService` and `models/dashboard.js`. Widgets accept mapped props only.

3. **Parallel fetch in `AdminDashboard`** — One `Promise.all` loads KPIs and all three widgets in a single round trip (four independent queries, no N+1).

4. **Per-widget error isolation** — KPI failure shows the existing dashboard error card; widget failures show inline retry without blocking other sections.

5. **Low stock threshold** — Uses shared `LOW_STOCK_THRESHOLD` (5) from `@/constants/inventory`. Query: `stock < 5` (includes out-of-stock). Severity: out (≤0), critical (1–2), warning (3–4).

6. **SKU column** — Products table has no SKU field. The widget shows a **Ref** column (first 8 chars of product UUID, uppercase) as a stable product reference.

7. **Activity user** — `order_events` does not store actor IDs. The feed shows the **order customer's** `full_name` when available (no email/phone exposed).

8. **Navigation** — Existing routes only: orders → `/admin/orders/:id`, products → `/admin/products/:id/edit` (no dedicated product detail route exists).

9. **No charts** — Per milestone scope, no recharts or reporting UI was added.

---

## Testing summary

| Suite | Result |
|---|---|
| `npm test` | 164 tests passing (+25 new) |
| `npm run lint` | Clean |
| `npm run build` | Success |

New coverage:

- Service methods: happy path + error fallback
- Model mappers: orders, products, events, relative time, severity
- Widgets: render, skeleton, empty, error, row/event navigation

Existing tests (checkout, orders, inventory, routing) unchanged and passing.

---

## Known limitations

1. **KPI revenue aggregation** — Still client-side sum of all order totals (4.1 limitation; unchanged).

2. **No per-product low-stock threshold** — Global constant only; schema has no `low_stock_threshold` column.

3. **Activity actor** — Events do not record which admin triggered a status change; feed shows customer name only.

4. **Initial load gate** — Full-page spinner until all four queries complete; widgets support skeleton props for future incremental loading.

5. **Product reference** — UUID prefix used instead of SKU until a SKU column is added to the schema.

---

## Next milestone recommendations

1. **Revenue time-series chart** — Add `getRevenueTimeSeries()` with SQL/RPC aggregation; compose a chart widget below KPIs.

2. **SKU field** — Migration to add `sku` to `products`; update `mapLowStockProductRow` to use real SKUs.

3. **Activity actor** — Extend `log_order_event()` payload with `actor_id` for admin attribution in the feed.

4. **Incremental widget refresh** — Optional polling or Supabase realtime on `order_events` for live activity.

5. **Server-side KPI RPC** — Replace client-side revenue sum for scale.

6. **Export / reports** — CSV export for orders and inventory as a separate reporting milestone.

---

## Acceptance criteria

| Criterion | Met |
|---|---|
| New analyticsService methods | ✅ |
| Recent Orders widget functional | ✅ |
| Low Stock widget functional | ✅ |
| Recent Activity widget functional | ✅ |
| Navigation works | ✅ |
| Presentation-only components | ✅ |
| Existing functionality unchanged | ✅ |
| Tests pass | ✅ |
| Build succeeds | ✅ |
| Documentation updated | ✅ |
