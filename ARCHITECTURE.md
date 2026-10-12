# ARCHITECTURE

Status: **proposed design**, nothing implemented. Requirements: [PROJECT_SPEC](PROJECT_SPEC.md). Schema: [DATABASE](DATABASE.md). Threats and controls: [SECURITY](SECURITY.md).

## 1. Principles

1. Simple: one SPA plus Supabase. No separate backend, Redis, chat server or extra infrastructure without a documented requirement.
2. The database is the authority. The browser only presents and requests.
3. Organizational title, operational roles and application permissions are separate (separate tables, separate checks).
4. Privileged actions run in narrowly scoped database functions (or an Edge Function where a secret is needed), never as direct table writes from the client.
5. Every protected table has RLS; client-side visibility checks are never the sole control.
6. Schema changes only through versioned migrations.

## 2. System overview

```
 Phone / Desktop browser (installed PWA)
 ┌───────────────────────────────────────┐
 │ React + TS + Vite + Tailwind          │
 │ service worker (shell cache only)     │
 │ supabase-js (anon/publishable key)    │
 └───────┬───────────────┬───────────────┘
         │ HTTPS         │ WebSocket
         ▼               ▼
 ┌──────────────────────────────────────────────┐
 │ Supabase                                     │
 │  Auth (JWT) ── PostgREST/RPC ── Realtime     │
 │        │              │             │        │
 │        └──── PostgreSQL + RLS ──────┘        │
 │             privileged functions, triggers   │
 │  Edge Function: push sender (service secrets)│
 └──────────────────────────────────────────────┘
         │ Web Push (generic payload)
         ▼
 Browser push service → device
```

Static frontend hosting is separate (D-04). The only secret-bearing component is the push Edge Function (D-09); the frontend holds only the public URL, public key and public VAPID key.

## 3. Frontend

Proposed structure (created in Phase 1):

```
src/
  app/            routing, providers, layout (bottom nav / sidebar)
  features/       one folder per area: auth, membership, team, roles, shifts,
                  availability, liveboard, incidents, helprequests,
                  announcements, handover, knowledge, notifications, admin
  components/ui/  reusable mobile-first primitives
  lib/            supabase client, query helpers, zod schemas, date/time utils
  types/          generated database types
  test/           test utilities
```

- Data access through one typed Supabase client in `lib/`; features call small hooks, not raw queries inside components.
- Server state via a query cache (TanStack Query proposed; added in Phase 1 only if justified, otherwise hooks); local UI state with React state.
- Zod validates input for UX; the database re-validates with constraints and function checks.
- Route guards (pending/approved/admin) improve UX only; denial of data is enforced by RLS.
- Every screen defines loading, empty, error and retry states.

## 4. Authentication and sessions

- Supabase Auth, email + password, email confirmation, password recovery (settings per D-13).
- JWT carries identity only; **authorization is evaluated in the database on every query** from membership and role tables, so suspending a member takes effect without waiting for token expiry.
- Sign-out clears local caches and drafts containing team data. Session expiry redirects to login with a clear message.
- Membership states: `pending → approved → suspended/removed`. Pending users reach only the Join Request status screen.

## 5. Authorization model

Layers (all required):
1. **Grants:** `anon` has no table access; `authenticated` receives only needed privileges; sensitive columns excluded from client write grants.
2. **RLS policies:** deny by default; every policy requires approved membership of the row's `team_id` via helper functions.
3. **Privileged functions:** `SECURITY DEFINER` with fixed `search_path`, explicit permission check inside, `EXECUTE` revoked from `PUBLIC`/`anon`.
4. **Audit:** privileged changes write to `audit_logs` inside the same transaction.

Permission bundles for Member, Team Lead, Admin, Superadmin are fixed in code/seed data (not a general permission editor). Superadmin is a separate `platform_owners` record, not an app role a client can touch.

### Privileged operation catalogue (proposed)

| Function | Caller | Purpose |
|---|---|---|
| `redeem_join_code(code, display_name, title)` | authenticated | Validate hash/expiry/uses/rate limit; create pending membership and join request |
| `review_join_request(id, decision)` | Admin+ | Approve/reject; transactional; audited |
| `suspend_member / reinstate_member` | Admin+ | Change membership status; audited |
| `grant_app_role / revoke_app_role` | Admin+ (Admin role: Superadmin only) | Permission bundle changes; audited |
| `create_join_code / revoke_join_code` | Admin+ | Returns raw code **once**; stores hash only |
| `claim_incident / assign_incident / resolve_incident / reopen_incident` | per matrix | Conditional updates preventing silent overwrite |
| `volunteer_help_request / confirm_assignment` | per matrix | Same conditional pattern |
| `submit_handover / acknowledge_handover` | per matrix | State transitions; items untouched |
| `publish_knowledge_note` | Team Lead+ | Publish and create revision |
| bootstrap script (SQL, not an RPC) | owner via dashboard | Insert first `platform_owners` row; see [SECURITY](SECURITY.md) §7 |

## 6. Data flow examples

**Reading the Live Ops Board:** client queries views/tables → RLS confirms approved membership → effective availability computed in a view (expired → Unknown) → client renders; Realtime keeps it fresh.

**Claiming an incident:** client calls `claim_incident(id)` → function checks membership and permission → `UPDATE … WHERE owner IS NULL` → zero rows updated returns a clear "already claimed" result → success writes an `incident_updates` system entry and a notification, in one transaction.

## 7. Realtime

- Subscribe to row changes for board-relevant tables (availability, shift assignments, incidents, help requests, announcements, notifications).
- Realtime applies RLS to change events (**validate** in Phase 2 with an unauthorized-persona test). Do not broadcast sensitive payloads on shared channels.
- Strategy: use events as a signal and refetch the affected query, so the displayed state always comes from an RLS-checked read.
- Show a connection indicator; on reconnect, refetch. Targets in [PROJECT_SPEC](PROJECT_SPEC.md) §8.

## 8. PWA and offline behaviour

- Web app manifest (name, icons, standalone display) and a service worker.
- Cache the application shell and static assets only. **Do not cache authenticated API responses** in the service worker (avoids stale or cross-user data on shared devices).
- Offline: show a disconnected banner; read-only cached shell; drafts (handover, knowledge) saved locally and clearly marked unsynced. No queued privileged mutations; the server rejects or conflicts newer data rather than being overwritten.
- Update flow: prompt the user to reload when a new version is available.

## 9. Notifications

- **In-app (Phase 3):** `notifications` rows created by database triggers/functions in the same transaction as the event; read/unread via `read_at`; preferences in `notification_preferences`.
- **Push (Phase 5):** user grants permission → subscription stored in `push_subscriptions` (own-row access only, never returned by ordinary profile queries) → an Edge Function, triggered from a notification insert (mechanism decided in Phase 5), validates recipient membership and sends a **generic** payload with no ticket details → tapping opens the authenticated app. Denied permission leaves core functionality intact.

## 10. Search

Knowledge search uses PostgreSQL full-text search (generated `tsvector` with GIN index) over title, tags and content, restricted by RLS to published notes (plus the author's own drafts). No external search service.

## 11. Environments and configuration

| Environment | Purpose | Notes |
|---|---|---|
| Local | Development | Vite dev server; Supabase dev project or local stack (D-08) |
| Dev | Shared testing | Hosted Supabase dev project; synthetic data only |
| Production | Real use | Separate Supabase project; migrations applied from Git; secrets in provider secret stores |

Variables: see [README](README.md) and `.env.example`. Only public values use the `VITE_` prefix.

## 12. Testing hooks

RLS and privileged functions are tested directly against the database as each persona ([TEST_PLAN](TEST_PLAN.md)); UI tests never substitute for these.

## 13. Architecture decisions

| ID | Decision | Alternative rejected |
|---|---|---|
| ADR-01 | Supabase-native; no custom backend | Python/Node API (more infrastructure and secrets) |
| ADR-02 | Privileged writes via DB functions with internal checks | Direct table writes with permissive RLS |
| ADR-03 | Fixed permission bundles | General-purpose permission editor (larger attack surface) |
| ADR-04 | Superadmin kept outside client-writable tables | A role flag on profiles |
| ADR-05 | Events trigger refetch, not trusted payloads | Rendering raw realtime payloads |
| ADR-06 | Service worker caches shell only | Caching API data for offline use |
