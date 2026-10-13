# TEST_PLAN

Status: **plan only**. No tests exist and none have been run. Results are recorded in [PROJECT_STATE](PROJECT_STATE.md) and [CHANGELOG](CHANGELOG.md) only after real execution, with the actual command output. Criteria: [PROJECT_SPEC](PROJECT_SPEC.md) §7. Phase mapping: [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md). Controls: [SECURITY](SECURITY.md).

## 1. Strategy

| Level | Tool | Scope |
|---|---|---|
| Static | TypeScript, oxlint, Prettier | Every commit; also CI |
| Unit | Vitest | Pure logic: availability expiry display, validation schemas, formatting, permission helpers on the client (cosmetic only) |
| Component | Vitest + React Testing Library | Screens' loading/empty/error states, forms, role-based visibility (cosmetic) |
| Database / RLS | SQL tests (pgTAP via Supabase CLI, proposed) and/or Vitest integration tests with real JWTs per persona | Policies, privileged functions, constraints, migrations from empty database |
| Integration | Vitest against a dev Supabase project or local stack (D-08) | Workflows end to end through the API |
| End to end | Playwright | Key user journeys on mobile and desktop viewports |
| Manual | Checklists below | Real devices, install, push, usability |

Principle: **security is proven at the database/API level.** A UI test that hides a button is not evidence of access control.

## 2. Test personas and data

Anonymous · Pending · Member A · Member B · Team Lead · Admin · Superadmin · Suspended member · Member of a second team (isolation). Synthetic data only; test credentials live in a git-ignored env file. Each persona authenticates with a real session so tests exercise genuine JWTs.

## 3. RLS and security tests

Each case needs an **allow** and a **deny** assertion where applicable, executed directly against the API/database.

| ID | Case | Expected |
|---|---|---|
| SEC-01 | Anonymous reads/writes every protected table | Denied |
| SEC-02 | Pending user reads directory, incidents, announcements, handovers, knowledge | Denied; may read own request only |
| SEC-03 | Member updates own `membership_status` | Denied |
| SEC-04 | Member inserts/updates `member_app_roles`, `app_roles`, `platform_owners` | Denied |
| SEC-05 | Repeated wrong join codes | Rejected; rate limit triggers; uniform error |
| SEC-06 | Expired, revoked, exhausted, unknown code | Rejected; raw code not in logs; hash not readable by clients |
| SEC-07 | Any client path creates/promotes Superadmin (signup metadata, profile update, RPC) | Impossible |
| SEC-08 | Remove last Superadmin via app path | Blocked |
| SEC-09 | Recovery runbook on dev project | Owner access restored without UI |
| SEC-10 | Scan Git history, `.env*`, built bundle, logs for service-role/VAPID/secret patterns | None found |
| SEC-11 | User of team 2 reads/writes team 1 rows | Denied |
| SEC-12 | Suspend member while holding a valid JWT | Next request denied |
| SEC-13 | Call privileged functions as anon/member/wrong role; inspect `search_path` and `EXECUTE` grants | Denied; grants minimal |
| SEC-14 | Script/HTML in announcement and note content | Rendered inert |
| SEC-15 | Push payload contents; read another user's subscription | Generic text; denied |
| SEC-16 | Update/delete `audit_logs`; read as Member | Denied |
| SEC-17 | After sign-out, check caches and local storage | No team data remains |
| SEC-18 | Two simultaneous claims on one incident/help request | One wins; other gets conflict; no silent overwrite |
| SEC-19 | Burst of incident/announcement/notification creation | Rate limited |
| SEC-20 | `npm audit` and lockfile check | Reviewed; no unapproved dependency |
| SEC-21 | Suspended or other-team user subscribed to Realtime | Receives no events |
| SEC-22 | CI check that every `public` table has RLS enabled | Fails build if not |
| SEC-23 | Call each sensitive Admin/Superadmin function with an aal1 (non-MFA) session | Denied; aal2 session allowed (D-13) |
| SEC-24 | Redeem a code anonymously, and with an unconfirmed-email account | Rejected |

## 4. Membership workflow tests

Sign up → confirm email → sign in → redeem (D-03); redemption without an authenticated, confirmed session fails; a signed-in user without membership sees no team data. Valid code → pending (AC-M1); invalid/expired/revoked/exhausted rejected and rate-limited (AC-M2); only Admin approves/rejects and grants Member/Team Lead; only Superadmin grants Admin (AC-M3, D-06); approval is transactional and audited; self-approval and re-redeeming to bypass review fail; suspension removes access and keeps history (AC-M6); reinstatement works; rejected user cannot re-enter without a new code and review.

## 5. Criteria-to-test mapping

| Criteria | Level | Phase |
|---|---|---|
| AC-M1–M3, M6 | RLS/integration, E2E for approval flow | 1 |
| AC-M4, M5 | Integration, component | 2 |
| AC-L1, L2 | Unit (effective status), integration | 2 |
| AC-L3, L5 | Integration, manual (two devices) | 2 |
| AC-L4 | E2E mobile viewport; incident part after Phase 3 | 2, 3 |
| AC-I1–I5 | Integration, concurrency tests, E2E "simulated outage" | 3 |
| AC-H1, H2, H5 | Integration, component | 3 |
| AC-N1 | Integration, component | 3 |
| AC-H3, H4, H5 | Integration, E2E handover | 4 |
| AC-N4, N5 | RLS (draft isolation), integration (search, revisions) | 4 |
| AC-N2, N3 | Manual on real devices; integration for sender; component for denied permission | 5 |
| AC-S1–S3 | SEC-01, 02, 11, 03, 04, 10 — run from Phase 1 and re-run in Phase 5 | 1, 5 |
| AC-S4 | Manual and Playwright (install, refresh, sign-out, expiry) | 5 |
| AC-S5 | Playwright viewports and manual | 2–5 |
| AC-S6 | Fresh-database migration run; backup/restore drill | 1, 5 |
| AC-S7 | `build`, full test suite, Playwright smoke | 5 |
| AC-S8–S10 | SEC-07, 08, 09 | 1, 5 |

## 6. End-to-end flows (Playwright)

1. Join: Admin creates code → new user redeems → pending screen → Admin approves → user sees Live Ops Board.
2. Unauthorized: pending/suspended user attempts protected URLs → no data.
3. Availability: set status with expiry → expires to Unknown.
4. Simulated outage: report incident → claim → updates → help request → volunteer → confirm → resolve.
5. Announcement: publish, pin, acknowledge.
6. Handover: create, add items, submit, acknowledge; items stay unresolved.
7. Knowledge: draft → publish → search → revision view.
8. Install, offline banner, sign-out clears data.

## 7. Manual checklists

**Mobile (real devices, D-16):** layouts at narrow widths; bottom navigation reachable one-handed; keyboard behaviour in forms; install to home screen; push permission allow and deny; background notification tap opens the correct screen; poor-network behaviour and reconnect.
**Admin:** code rotation/revocation; role create/rename/deactivate; suspend/reinstate; audit log readable.
**Recovery:** follow the written runbook from a clean machine.

## 8. Entry/exit rules

- A phase is "done" only when its criteria pass, the diff has been reviewed, and results are recorded.
- A failing security test blocks the phase gate; it is never deferred to meet a schedule.
- Flaky tests are fixed or removed with a recorded reason, never silently skipped.
- Report counts and outputs exactly as observed; if a suite was not run, say so.

## 9. CI (Phase 1a onward)

Typecheck, lint, unit/component tests, build, secret scan, migration-from-empty check, RLS-enabled check (SEC-22). Playwright smoke added in Phase 5.

**Database tests (Phase 1b):** pgTAP files in `supabase/tests/database/`, run with `npm run db:test` (needs Docker and the local Supabase stack) or `supabase test db --linked`. SEC-22 is implemented there (assertion 4). A CI job running `supabase start`, `db reset` and `db test` is **not yet wired** (needs Docker on the runner and is unverified); candidate for Phase 1e. The assertion that no policies exist is intentionally temporary and must be revised in Phase 1d when the first client policies are added.
