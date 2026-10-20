# TEST_PLAN

Status: **plan only**. No tests exist and none have been run. Results are recorded in [PROJECT_STATE](PROJECT_STATE.md) and [CHANGELOG](CHANGELOG.md) only after real execution, with the actual command output. Criteria: [PROJECT_SPEC](PROJECT_SPEC.md) §7. Phase mapping: [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md). Controls: [SECURITY](SECURITY.md).

## 1. Strategy

| Level | Tool | Scope |
|---|---|---|
| Static | TypeScript, oxlint, Prettier | Every commit; also CI |
| Unit | Vitest | Pure logic: availability expiry display, validation schemas, formatting, permission helpers on the client (cosmetic only) |
| Component | Vitest + React Testing Library | Screens' loading/empty/error states, forms, role-based visibility (cosmetic) |
| Database / RLS | SQL verification script (`supabase/tests/verify.sql`, no Docker) and/or Vitest integration tests with real JWTs per persona | Policies, privileged functions, constraints, migrations from empty database |
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

**Database tests (Phases 1b–2a):** `supabase/tests/verify.sql` is one rollback-only statement (329 checks: RLS on every table, the exact policy set, privilege and function-execute inventories, constraints, append-only audit, and the whole joining, approval, suspension, role-grant, code, Superadmin bootstrap and recovery workflow including MFA, self-action and cross-team refusals, plus a persona matrix of eight personas: stranger, pending/approved newcomer, plain member, Team Lead, suspended member, Admin, other-team Admin and Superadmin). It needs no Docker or extensions. Run it with `npm run db:verify` (hosted dev project via the CLI) or paste it into the dashboard SQL editor; it always ends with a deliberate error whose first line is `VERIFY RESULT: PASS` or `FAIL`. `supabase test db` (pgTAP) was dropped because it requires Docker even for a remote database. SEC-22 is implemented there. The CI `database` job (workflow `ci.yml`) applies the migrations to an empty PostgreSQL 16 service container, with `supabase/tests/ci/stub_supabase.sql` standing in for Supabase's roles and `auth` schema, and runs `verify.sql`. The commands were run locally; **the GitHub Actions run itself has not been seen**. The check that the policy set is exactly the expected list must be updated whenever a policy is added (Phase 1e adds admin read policies). Lesson recorded: test cases must resolve row IDs as the table owner; looking them up as the acting user hides rows under RLS and makes denial tests pass for the wrong reason.

**Frontend auth tests (Phase 1c):** `src/features/auth/*.test.tsx`, `src/features/profile/*.test.tsx`, `src/App.test.tsx` use a hand-written fake Supabase client (`src/test/fakeSupabase.ts`). They are **mocked**: they prove how our code reacts to Supabase responses, not how real Supabase Auth behaves. Real-Supabase integration tests do not exist yet; see the manual checklist below.

## 10. Manual auth checklist (needs a hosted dev project; not yet run)

1. Sign up with a new address; confirm the email arrives; open the link on the **same** device; land signed in at the account page with "not a team member".
2. Repeat on a different browser/device than the one used to sign up (expected to fail with the default PKCE template; passes only after the token-hash template change, D-19).
3. Sign up again with the same address: the screen shows the same message; no second email is required.
4. Wrong password shows the generic message; five rapid attempts eventually show the rate-limit message.
5. Forgot password for a real and a non-existent address: identical message; real address receives a link; the link opens the reset form only; weak and mismatched passwords are refused; success returns to the account page; old password no longer works.
6. Open a recovery link, then close the tab without finishing: reopen the app and confirm what state it shows; sign out and confirm no stale recovery session remains.
7. Sign out, then use the browser Back button: no protected content appears.
8. In another tab, sign out; the first tab returns to sign-in with the "session has ended" notice.
9. Create and edit the profile; confirm in the dashboard that only `display_name` and `organizational_title` changed.
10. Run `npm run db:verify`: expect `VERIFY RESULT: PASS (329 passed, 0 failed)`.
11. Joining (no Admin exists yet, so only up to pending): create a synthetic dev join code in the SQL editor by inserting a `join_codes` row whose `code_hash` is the SHA-256 hex of a code you choose (see below), sign up and confirm a user, enter the code on the join screen, and confirm the waiting screen. Confirm in the dashboard that the membership is `pending`, the profile exists, and `join_codes.use_count` is 1. Entering a wrong code shows the generic message; five wrong codes shows the rate-limit message.
12. Confirm in Project Settings, API that `private` is **not** in the exposed schemas (R-21).

Hash for step 11 (SQL editor, owner role): `select encode(sha256(convert_to('YOURCODEHERE0001', 'UTF8')), 'hex');` then insert it with an `expires_at` in the future, `max_uses` 1 and your team's id. Use synthetic data only.
13. Superadmin (needs the runbook): bootstrap your owner account; sign in; confirm the Administration section appears; set up an authenticator app; confirm actions are disabled until the code is verified; create a joining code (shown once); approve a test member; suspend and reinstate them; confirm a plain member sees no Administration section.
14. Confirm a second run of the bootstrap statement is refused, and that `recovery := true` adds a second Superadmin.
15. Confirm in the dashboard that `platform_owners` cannot be read through the Table editor's API view and that no other role can execute `private.bootstrap_superadmin`.
16. Operational roles (as an Admin with MFA): confirm the six seeded roles; create a role; rename it; assign two roles to one member and make one primary; deactivate a role and confirm it disappears from member chips but stays on the Admin list; confirm an inactive role cannot be assigned.
17. As an ordinary member: confirm the directory lists approved members only, searches by name, title and role, and shows no Role administration section; as a pending or suspended user, confirm no directory.
