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
| `/dashboard` | `AdminDashboard` | KPIs + 7-day revenue chart (recharts) | `adminService.getStats` |
| `/products` | `AdminProducts` | list/delete products | `products` |
| `/products/new`, `/products/:id/edit` | `AdminProductForm` | create/update product, image upload | `products`, Storage `products` bucket |
| `/orders`, `/orders/:id` | `AdminOrders`, `AdminOrderDetail` | list, view, update status | `orders`, `order_items`, `profiles` |
| `/users` | `AdminUsers` | list users, change role | `profiles` |
| `/inventory` | `AdminInventory` | stock + low-stock view/update | `products` |
| `/pickup-locations` | `AdminPickupLocations` | CRUD pickup locations | `pickup_locations` (unverified) |
| `/settings` | `AdminSettings` | **placeholder only** ("Configuration Module Offline") | — |

## 3. Service (`adminService`)
- `getStats` — parallel counts (`head:true`) + client-side revenue aggregation (does not scale).
- Orders: `getOrders`, `getOrder`, `updateOrderStatus`.
- Users: `getUsers`, `updateUserRole`.
- Products: `createProduct`, `updateProduct`, `deleteProduct`, `uploadImages`.
- Categories: `createCategory`/`updateCategory`/`deleteCategory` → target a `categories` table that is **unverified** and contradicts the text-based `products.category` used elsewhere.
- Inventory: `getInventory`, `getLowStock` (`stock < 5`), `updateStock`.
- Pickup locations: full CRUD (table unverified).

## 4. Known issues (see audits)
- `AdminSettings` is a non-functional placeholder.
- `uploadImages` returns `undefined` URLs (`getPublicUrl` mis-destructured); Storage bucket/policies unverified.
- Categories model is contradictory (table CRUD vs derived text).
- Revenue computed client-side over all orders — move to SQL/RPC.
- `updateUserRole` is the intended role-change path, but the `profiles` RLS flaw lets users self-escalate outside it (CRITICAL).

## 5. Target conventions
- Privileged writes validated in-database; storage policies explicit; stats via SQL aggregates.
