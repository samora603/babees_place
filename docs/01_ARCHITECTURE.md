# Application Architecture

## Architecture

React Frontend

↓

React Router

↓

Services Layer

↓

Supabase Client

↓

Supabase

↓

PostgreSQL

---

## Authentication Flow

User

↓

Login

↓

Supabase Auth

↓

JWT

↓

Protected Routes

↓

Role Check

↓

Customer Dashboard

or

Admin Dashboard

---

## Layers

Presentation Layer

Business Logic Layer

Data Access Layer

Database Layer

Storage Layer

---

## Folder Responsibilities

components/

Reusable UI

pages/

Route pages

layouts/

Application layouts

hooks/

Reusable React hooks

context/

Global state

services/

Communication with Supabase

lib/

Configuration

utils/

Helper functions

assets/

Images

---

## Current Implementation Notes (synced Phase 0)

- The layered model above is accurate: `pages → context/hooks → services → lib/supabaseClient → Supabase`.
- There is **no custom backend**; the "Services Layer" talks directly to Supabase (PostgREST/Auth/Storage) plus one RPC (`place_order`). A legacy `axios` client (`services/api.js`) is unused.
- Global state uses React Context (`Auth`, `Cart`, `Wishlist`).
- **Known deviation:** `Navbar`/`Footer` are currently rendered only on the `/` route (a shared layout is a Phase 1 fix). See `docs/technical/06_Frontend.md`.
- For the concrete, current file tree see `docs/architecture/Current_Project_Structure.md`.
- Diagrams (C4 / sequence / ERD) are **not yet present** and are a documentation gap tracked for Phase 1.
