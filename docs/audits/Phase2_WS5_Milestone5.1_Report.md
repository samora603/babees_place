# Phase 2 Workstream 5 — Milestone 5.1 Implementation Report

**Customer Profile Foundation**  
Date: 2026-07-13  
Status: Complete

---

## Features implemented

| Feature | Status |
|---|---|
| `customer_addresses` table with RLS | ✅ |
| `customer_preferences` table with RLS | ✅ |
| Single default address enforcement (trigger) | ✅ |
| Address CRUD service (`addressService`) | ✅ |
| Preferences upsert service (`customerProfileService`) | ✅ |
| Profile page: Personal Information | ✅ |
| Profile page: Address Book | ✅ |
| Profile page: Account Preferences | ✅ |
| Checkout: select saved address | ✅ |
| Checkout: add new address (optional save) | ✅ |
| Checkout: one-time address without saving | ✅ |
| Checkout: preference defaults (fulfillment / pickup) | ✅ |
| Unit & integration tests | ✅ |
| Documentation | ✅ |

---

## Database changes

Migration: `supabase/migrations/014_customer_profile.sql`

### `public.customer_addresses`

| Column | Type | Notes |
|---|---|---|
| `id` | uuid PK | |
| `user_id` | uuid FK → `profiles(id)` CASCADE | |
| `label` | text | `home`, `work`, `other` |
| `recipient_name` | text | |
| `phone` | text | normalized in app layer |
| `county` | text | |
| `town` | text | |
| `street_address` | text | |
| `additional_directions` | text | optional |
| `is_default` | boolean | one per user via trigger |
| `created_at` / `updated_at` | timestamptz | `set_updated_at` trigger |

### `public.customer_preferences`

| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid PK FK → `profiles(id)` CASCADE | one row per customer |
| `preferred_fulfillment` | text | `pickup` \| `delivery` \| null |
| `preferred_pickup_location_id` | uuid FK → `pickup_locations` SET NULL | |
| `marketing_emails` | boolean | storage only (no sender) |
| `sms_notifications` | boolean | storage only (no sender) |
| `created_at` / `updated_at` | timestamptz | |

### Security

- RLS enabled on both tables.
- Policies: SELECT / INSERT / UPDATE / DELETE where `user_id = auth.uid()`.
- No service-role usage from the frontend.
- `enforce_single_default_address()` trigger clears other defaults when one is set.

---

## Services added

| Service | Responsibility |
|---|---|
| `addressService.js` | CRUD, default selection, first-address auto-default, promote on default delete |
| `customerProfileService.js` | Preferences get/upsert, `getProfileBundle()` parallel fetch |

Models: `models/address.js`, `models/preferences.js` — validation, mapping, checkout adapter.

---

## Files changed

### New

| File | Purpose |
|---|---|
| `supabase/migrations/014_customer_profile.sql` | Address book + preferences schema |
| `frontend/src/models/address.js` | Address types, validation, checkout mapping |
| `frontend/src/models/preferences.js` | Preferences types and validation |
| `frontend/src/services/addressService.js` | Address CRUD |
| `frontend/src/services/customerProfileService.js` | Preferences + profile bundle |
| `frontend/src/components/profile/ProfileSection.jsx` | Reusable profile section shell |
| `frontend/src/components/profile/PersonalInfoForm.jsx` | Name / phone / email |
| `frontend/src/components/profile/AddressForm.jsx` | Reusable address form |
| `frontend/src/components/profile/AddressBook.jsx` | Address list, modal, delete confirm |
| `frontend/src/components/profile/AccountPreferencesForm.jsx` | Fulfillment + notification prefs |
| `frontend/src/components/checkout/CheckoutDeliverySection.jsx` | Checkout address UX |
| `frontend/src/models/address.test.js` | Model tests |
| `frontend/src/models/preferences.test.js` | Model tests |
| `frontend/src/services/addressService.test.js` | Service tests |
| `frontend/src/services/customerProfileService.test.js` | Service tests |
| `frontend/src/components/checkout/CheckoutDeliverySection.test.jsx` | Component tests |
| `frontend/src/test/migration-014.test.js` | Migration smoke tests |
| `docs/audits/Phase2_WS5_Milestone5.1_Report.md` | This report |

### Modified

| File | Change |
|---|---|
| `frontend/src/pages/Profile.jsx` | Three-section profile layout |
| `frontend/src/pages/Checkout.jsx` | Saved/new/one-time address modes, preference bootstrap |
| `frontend/src/test/order-checkout-flow.test.js` | Address integration assertions |
| `docs/technical/06_Frontend.md` | Profile + checkout architecture |
| `docs/technical/04_Authentication.md` | Customer profile data ownership |
| `docs/database/Migration_History.md` | Migration 014 entry |

---

## Architecture decisions

1. **Extend, don't replace** — Saved addresses map to the existing checkout `delivery_address` JSONB shape via `addressToCheckoutDelivery()`; `place_order` RPC unchanged.

2. **No profile duplication** — Addresses and preferences live in dedicated tables; `profiles` retains identity fields only.

3. **Services own business logic** — Components handle presentation and local form state; validation in models.

4. **Parallel fetch** — `getProfileBundle()` loads addresses + preferences once for profile and checkout bootstrap.

5. **Checkout modes** — `saved` | `new` | `once` preserves one-time delivery without forcing address book adoption.

6. **Notification flags stored only** — `marketing_emails` and `sms_notifications` persisted for future milestones; no delivery system in 5.1.

---

## Testing summary

| Area | Coverage |
|---|---|
| Address model validation & mapping | ✅ |
| Preferences model validation & mapping | ✅ |
| `addressService` CRUD / default / errors | ✅ |
| `customerProfileService` upsert / bundle | ✅ |
| Checkout address → order payload | ✅ |
| `CheckoutDeliverySection` empty / modes | ✅ |
| Migration 014 structure & RLS | ✅ |

Run: `npm test` from `frontend/`.

---

## Known limitations

1. **Migration apply** — `014_customer_profile.sql` must be applied to the target Supabase project before features work in production.

2. **No geocoding** — County/town are free text; no address verification API.

3. **Notification preferences** — Stored but not connected to email/SMS providers.

4. **`userService.js` stubs** — Legacy address stubs remain unused; superseded by `addressService`.

5. **Save-on-checkout failure** — If optional address save fails during checkout, the order still proceeds with the entered delivery details.

---

## Acceptance criteria

| Criterion | Met |
|---|---|
| Multiple saved addresses | ✅ |
| Default address | ✅ |
| Checkout uses saved addresses | ✅ |
| Customer profile expanded | ✅ |
| Preferences persisted | ✅ |
| Services separated from UI | ✅ |
| RLS implemented | ✅ |
| Existing checkout functional | ✅ |
| Tests pass | ✅ |
| Build succeeds | ✅ |
| Documentation updated | ✅ |
