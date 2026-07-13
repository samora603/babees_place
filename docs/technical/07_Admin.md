# Admin Dashboard — Technical Reference

Status: Starter content populated during Phase 0.
Source of truth: `frontend/src/pages/admin/*`, `frontend/src/components/layout/{AdminLayout,AdminRoute}.jsx`, `frontend/src/services/adminService.js`.

---

## 1. Access control
- Guarded by `AdminRoute` (requires `profile.role === 'admin'`) wrapping `AdminLayout` (nested `<Outlet/>`).
- Server-side enforcement via RLS (`orders_update_admin`, `is_admin()`, `profiles` admin read). Frontend guard is UX only.

## 2. Screens (routes under `/admin`)
| Route | Page | Function | Backing |
|---|---|---|---|
| `/dashboard` | `AdminDashboard` | KPI cards (revenue, orders, products, clients) | `analyticsService.getDashboardSnapshot` |
| `/products` | `AdminProducts` | list/delete products | `products` |
| `/products/new`, `/products/:id/edit` | `AdminProductForm` | create/update product, image upload | `products`, Storage `products` bucket |
| `/orders`, `/orders/:id` | `AdminOrders`, `AdminOrderDetail` | list, view, update status | `orders`, `order_items`, `profiles` |
| `/users` | `AdminUsers` | list users, change role | `profiles` |
| `/inventory` | `AdminInventory` | stock + low-stock view/update | `products` |
| `/pickup-locations` | `AdminPickupLocations` | CRUD pickup locations | `pickup_locations` (unverified) |
| `/settings` | `AdminSettings` | **placeholder only** ("Configuration Module Offline") | — |

## 3. Services
- **Analytics (`analyticsService`)** — `getDashboardSnapshot` for dashboard KPIs. See `docs/technical/11_Analytics.md`.
- **Admin (`adminService`)** — orders (`getOrders`, `getOrder`, `updateOrderStatus`), users, products, inventory, pickup locations, categories.

## 4. Known issues (see audits)
- `AdminSettings` is a non-functional placeholder.
- `uploadImages` returns `undefined` URLs (`getPublicUrl` mis-destructured); Storage bucket/policies unverified.
- Categories model is contradictory (table CRUD vs derived text).
- Revenue computed client-side over all orders — move to SQL/RPC.
- `updateUserRole` is the intended role-change path, but the `profiles` RLS flaw lets users self-escalate outside it (CRITICAL).

## 5. Target conventions
- Privileged writes validated in-database; storage policies explicit; stats via SQL aggregates.
