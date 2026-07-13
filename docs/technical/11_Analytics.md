# Analytics — Technical Reference

Status: Dashboard charts & visualizations (Milestone 4.4)  
Source of truth: `frontend/src/services/analyticsService.js`, `frontend/src/models/analytics.js`, `frontend/src/models/chartPresentation.js`, `frontend/src/components/admin/dashboard/*`, `frontend/src/pages/admin/AdminDashboard.jsx`

---

## 1. Purpose

The admin analytics layer provides KPI cards, business metrics, operational widgets, and Recharts visualizations. All Supabase access stays in `analyticsService` (unchanged since 4.3). Chart components are presentation-only and consume existing API responses.

### In scope

**Foundation (4.1–4.2)** — KPIs, recent orders, low stock, activity feed

**Business metrics (4.3)** — revenue/sales summaries, aggregation APIs, top products/categories tables

**Visualizations (4.4)**

- `RevenueTrendChart` — vertical bar chart from `getRevenueSummary()` data
- `OrdersStatusChart` — horizontal bar chart from `getOrdersByStatus()`
- `FulfillmentChart` — donut chart from `getOrdersByFulfillment()`
- `PaymentStatusChart` — pie chart from `getOrdersByPaymentStatus()`
- Enhanced `TopProductsWidget` / `TopCategoriesWidget` with relative bars
- Lazy-loaded Recharts via `React.lazy` + `Suspense`

### Out of scope

- Server-side SQL/RPC aggregates
- Exportable reports
- Changes to `analyticsService` public APIs

---

## 2. Architecture

```
AdminDashboard
    │
    ├── Promise.all — existing analyticsService methods (unchanged)
    │
    ├── Pass fetched props to summary cards + tables
    │
    └── Suspense + lazy(() => import chart components))
            │
            ▼
        models/chartPresentation.js  — shape API data for charts/bars
        constants/chartTheme.js      — palette aligned with design system
            │
            ▼
        Recharts (code-split chunk, loaded on dashboard route)
```

---

## 3. Chart architecture

| Component | Data source (already fetched) | Chart type |
|---|---|---|
| `RevenueTrendChart` | `RevenueSummary` | Vertical bar |
| `OrdersStatusChart` | `StatusCount[]` from `getOrdersByStatus` | Horizontal bar |
| `FulfillmentChart` | `StatusCount[]` from `getOrdersByFulfillment` | Donut |
| `PaymentStatusChart` | `StatusCount[]` from `getOrdersByPaymentStatus` | Pie |

Shared primitives:

| Component | Role |
|---|---|
| `DashboardChartFrame` | Loading / empty / error + `role="img"` wrapper |
| `ChartAccessibleTable` | Screen-reader table alternative (`sr-only`) |
| `RelativeBar` | Table row mini-bars (products + categories) |
| `ChartTooltipContent` | Branded Recharts tooltip |

Presentation adapters in `models/chartPresentation.js`:

- `revenueSummaryToChartData()`
- `statusCountsToChartData()`
- `topProductsToDisplayRows()` — adds `revenueBarPercent`
- `topCategoriesToDisplayRows()` — adds `revenuePercent`
- `isChartDataEmpty()`

**No calculations inside chart JSX** — components map props through adapters only.

---

## 4. Lazy loading strategy

Each chart module is imported with `React.lazy()` in `AdminDashboard.jsx`:

```javascript
const RevenueTrendChart = lazy(() => import('@/components/admin/dashboard/RevenueTrendChart'));
```

Vite emits a separate async chunk containing Recharts. The chunk loads when the admin dashboard mounts, not on the public storefront routes.

`Suspense` fallbacks reuse `DashboardWidgetCard` + `DashboardWidgetSkeleton` so layout does not shift.

---

## 5. Performance considerations

- **No duplicate business queries** — chart data reuses the same `Promise.all` results as summary cards (e.g. `revenueSummary` props shared by `RevenueSummaryCard` and `RevenueTrendChart`).
- **Order query deduplication** — `analyticsQueries.js` still dedupes in-flight `orders` / `order_items` fetches across aggregation methods.
- **Code splitting** — Recharts ~100KB+ gzip avoided on non-admin routes.
- **Client-side aggregation unchanged** — same MVP limits as 4.3.

---

## 6. Accessibility

- Each chart: `role="img"` + descriptive `aria-label`
- Hidden data table with caption for screen readers
- Pie/donut labels show **name, count, and percentage** (not color-only)
- `RelativeBar` uses `role="progressbar"` with `aria-valuenow`
- Chart container is keyboard-focusable (`tabIndex={0}`) with visible focus ring
- High-contrast palette from `constants/chartTheme.js` (brand gold + status colors)

---

## 7. Dashboard layout (4.4)

```
KPI Cards
Revenue Summary
Revenue Trend Chart
Sales Summary
Orders by Status | Fulfillment Distribution
Payment Status   | Top Categories
Recent Orders    | Low Stock
Top Products (full width)
Recent Activity
```

---

## 8. Revenue & aggregation reference (4.3, unchanged)

See prior sections in git history for `isRecognizedRevenueOrder`, status label mapping, and service method tables. **`analyticsService` was not modified in 4.4.**

---

## 9. Security

- AdminRoute + RLS unchanged
- Charts consume aggregated counts only — no new PII exposure

---

## 10. Tests

| File | Coverage |
|---|---|
| `models/chartPresentation.test.js` | Chart data adapters, bar percentages |
| `components/admin/dashboard/RevenueTrendChart.test.jsx` | Render, empty, error, loading |
| `components/admin/dashboard/OrdersStatusChart.test.jsx` | Render, empty |
| `components/admin/dashboard/FulfillmentChart.test.jsx` | Pie/donut + payment chart |
| `components/admin/dashboard/Top*Widget.test.jsx` | Enhanced table bars |

Recharts is mocked in chart component tests (jsdom has no layout engine).

Run: `npm test` from `frontend/`.

---

## 11. Extension points

- Add `getRevenueTimeSeries()` in a future milestone for daily line charts
- Server-side RPC when order volume requires it
- Optional: consolidate lazy charts into one `dashboardCharts` chunk if HTTP/2 overhead matters
