# CHANGELOG

All notable changes by phase. Format loosely follows Keep a Changelog. Test and build results appear here only when they were actually run.

## [Unreleased]

### Phase 2a — Operational roles and team directory (2026-10-18; unverified against real Supabase)

Built on request while the Phase 1 exit gate was still open (see PROJECT_STATE).

**Added**
- Migration `20261013000400_operational_roles.sql`: `operational_roles` and `member_operational_roles` (no client access); six seeded roles per team (BAU / Ticketing, Queue Manager, Onboarding, Resignation, Retain, Reconciliation); permission key `operational_roles.manage` in the Admin bundle (also added to existing Admin rows and to the Superadmin's reported permissions); functions `create_operational_role`, `update_operational_role`, `assign_operational_role`, `unassign_operational_role` (audited, MFA, Admin or Superadmin) and read functions `list_operational_roles`, `team_directory` (approved members; no e-mail addresses or user ids).
- Frontend `features/team`: `TeamDirectory` (searchable list with role chips, primary marked) shown to approved members; `RoleManager` (create, rename, deactivate or reactivate, assign with optional primary, remove) shown to holders of the permission through `AdminSection`; 27 more mocked tests (123 total).
- `verify.sql` extended to 329 checks (adds role and directory behaviour, new-table privilege and function inventories). New decision D-24.

**Changed**
- `AdminScreen` takes an optional `onAssurance` callback; the fake client's `rpc` returns empty lists for the two read functions.

**Verification (sandbox only)**
- `typecheck`, `lint`, `format:check`, `test` (123 passed), `build` exit 0. `verify.sql` PASS 329/329 on plain PostgreSQL 16. 12 planted database flaws and 5 planted UI flaws were each caught. Not verified: Windows, GitHub Actions, Supabase, real MFA behaviour.

### Phase 1e — Superadmin and administration (built across 2026-10-17 and 2026-10-18; unverified against real Supabase)

**Added**
- Migration `20261013000300_superadmin.sql` (**rebuilt on 2026-10-18**, see the PROJECT_STATE ledger): `platform_owners` (no API access) with a last-owner guard trigger; `private.is_superadmin`, `private.can_review_user`; `public.get_my_access`; owner-only `private.bootstrap_superadmin(user, team, name, recovery)`; reviewer read policies (`team_memberships_select_reviewers`, `join_requests_select_reviewers`, `profiles_select_reviewers`, `join_codes_select_managers`) with narrow column grants; Admin management in `grant_app_role`, `revoke_app_role`, `suspend_member` (Superadmin only for Admin, nobody can suspend a Superadmin).
- Frontend (from earlier work, now documented): `features/mfa` (TOTP enrolment and verification) and `features/admin` (`AdminSection`, `AdminScreen`: joining codes, approve or reject requests, suspend or reinstate members); 25 more mocked tests (96 total).
- `verify.sql` extended to 252 checks (adds bootstrap and recovery, last-owner guard, Superadmin powers, an eight-persona RLS matrix).
- `docs/RUNBOOK_SUPERADMIN.md`; CI `database` job with `supabase/tests/ci/stub_supabase.sql`.

**Changed**
- `20261013000200_membership.sql` (from earlier work): the `private`-schema default-privilege statement was replaced by a note; each new private function now needs an explicit `revoke ... from public`.
- `supabase/config.toml`: TOTP MFA enrolment and verification enabled for the local stack (hosted setting not changed).
- Fixed the fake client's `rpc` typing so `typecheck` passes (it failed on the earlier tests while `vitest` still passed).

**Incident**
- While starting this session the Phase 1e migration file was overwritten with a different design before it was noticed that an earlier version already existed (not in Git or any zip). It was reconstructed to the contract defined by the surviving `verify.sql` and frontend. Details and the open review item are in PROJECT_STATE.

**Verification (sandbox only)**
- `typecheck`, `lint`, `format:check`, `test` (96 passed), `build` exit 0. `verify.sql` PASS 252/252 on plain PostgreSQL 16, through the Supabase CLI without Docker, and by the CI job's commands run locally. 11 planted flaws in the new migration were each caught. Not verified: Windows, GitHub Actions, Supabase (local or hosted), real MFA and JWT behaviour, the bootstrap on Supabase.

### Phase 1d — Membership (2026-10-13, built by assistant; unverified against real Supabase)

**Added**
- Migration `20261013000200_membership.sql`: `team_memberships`, `app_roles` (fixed Member / Team Lead / Admin bundles, allowlisted permission keys, seeded per team), `member_app_roles`, `join_codes` (hash only), `join_requests`, `rate_limit_events`; helpers `private.is_approved_member`, `private.has_permission`, `private.require_aal2`; policies `teams_select_member`, `team_memberships_select_own`, `join_requests_select_own`; column-level read grants.
- Functions (SECURITY DEFINER, pinned `search_path`, EXECUTE for `authenticated` only, audited): `redeem_join_code`, `create_join_code`, `revoke_join_code`, `review_join_request`, `suspend_member`, `reinstate_member`, `grant_app_role`, `revoke_app_role`.
- Frontend `features/membership`: join form, waiting screen, approved placeholder, restricted screen; 18 more mocked tests (71 total).
- `verify.sql` extended to 150 checks (exact policy and privilege inventories, whole membership workflow, 12 refusal classes, audit completeness).
- New decisions D-21 (failure caps), D-22 (re-apply rules); risks R-16 to R-21.

**Changed**
- `AccountScreen` is now a shell around `MembershipGate`; `teams` and the other new tables are reachable only as described in DATABASE.md.
- D-02 implemented on its proposed default; still unconfirmed.

**Not built (by design)**
- No Superadmin, no way to grant Admin, no MFA enrolment, no admin screen or admin read policies: Phase 1e. Until then nobody can approve a request through the app.

**Verification (sandbox only)**
- `typecheck`, `lint`, `format:check`, `test` (71 passed), `build` exit 0. `verify.sql` PASS 150/150 on plain PostgreSQL 16 and through `supabase db query --db-url`; 12 planted database flaws and 4 planted frontend flaws were each caught. Not verified: Windows, GitHub Actions, Supabase local or hosted, real JWT `aal` claims, real Auth flows.

### Phase 1c — Authentication (2026-10-13, built by assistant; unverified against real Supabase)

**Added**
- Migration `20261013000100_profiles.sql`: `public.profiles` with own-row RLS (select/insert/update for `authenticated`), column-level write grants, no delete.
- `supabase/tests/verify.sql`: Docker-free, rollback-only verification (48 checks) replacing the pgTAP file; `npm run db:verify`.
- Frontend: `@supabase/supabase-js` and `zod` (dependencies); `lib/supabase.ts` (client, refuses service-role/secret keys); `features/auth` (sign-up with email confirmation, sign-in, sign-out with local fallback, password recovery, cross-device token links, `AuthProvider`, `RequireAuth`); `features/profile`; `no-console` lint rule.
- 53 mocked tests (fake Supabase client).
- README rewritten for Command Prompt and a Docker-free workflow; hosted Auth settings checklist; manual auth checklist in TEST_PLAN.
- New decisions D-19 (hosted Auth settings/email templates), D-20 (SMTP).

**Changed**
- `supabase/config.toml` local auth values: email confirmation on, secure password change on, minimum password 12 with lower/upper/digits, site URL and redirect `http://localhost:5173`. Hosted project not changed.
- `npm run db:test` (pgTAP, needs Docker) removed; `AGENTS.md` now specifies CMD.

**Verification (sandbox only)**
- `typecheck`, `lint`, `format:check`, `test` (53 passed), `build` exit 0. `verify.sql` PASS 48/48 on plain PostgreSQL 16 (also through `supabase db query --db-url`). Mutation checks: 7 weakened migrations and 4 broken frontend behaviours were all detected.
- Not verified: Windows, GitHub Actions, Supabase local stack, hosted dev project, real Auth flows.

**Correction**
- The Phase 1b instruction to run `supabase test db --linked` could not work without Docker.

### Phase 1b — Database foundation (2026-10-13, built by assistant; owner verification pending)

**Added**
- Supabase CLI (`supabase` ^2.120.0, dev dependency), `supabase/config.toml` (`project_id = "uam-connect"`), `db:start|stop|reset|test` scripts.
- Migration `20261013000000_baseline_teams_audit.sql`: `private` schema and three SECURITY INVOKER helpers, `teams`, append-only `audit_logs`; RLS enabled, no policies, all API-role privileges revoked.
- `supabase/seed.sql`: one synthetic team with a fixed UUID, idempotent.
- `supabase/tests/database/001_baseline.test.sql`: 35 pgTAP assertions (RLS, privileges, constraints, append-only, role denial).
- README Supabase workflow; DATABASE.md implementation status and decisions.

**Changed**
- `teams.incident_seq` deferred to Phase 3.

**Verification (sandbox)**
- Clean PostgreSQL 16.15 with stub API roles: migration applied; 35/35 pgTAP passed; seed ran three times leaving 1 row; mutation checks (no revokes, no audit triggers, RLS off) each made tests fail as expected.
- Not verified: Supabase local stack (no Docker here), linked dev project, CI database job. D-17 and Phase 1a owner acceptance remain unconfirmed.

### Phase 1a — Scaffold (2026-10-13, built by assistant; owner verification pending)

**Added**
- Vite 8 + React 19 + TypeScript 6 scaffold (create-vite 9.2.1, `react-ts`), Tailwind CSS 4 via `@tailwindcss/vite`, Vitest 5 + React Testing Library + jest-dom, Prettier, oxlint (create-vite default; used instead of ESLint).
- Scripts: `typecheck`, `lint`, `test`, `test:watch`, `format`, `format:check`, `build`.
- `.nvmrc` (22), `engines >=22.12.0`, `.gitignore` rules protecting `.env*` (except `.env.example`), GitHub Actions CI (typecheck, lint, format check, test, build).
- Minimal app shell and one smoke test.

**Removed**
- Vite template demo assets and `App.css`, and the template README (replaced by the project README).

**Verification (sandbox only)**
- Node v22.22.2, npm 10.9.7: `typecheck`, `lint` (0 warnings, 0 errors), `format:check`, `test` (1 passed) and `build` all exited 0; built CSS contains Tailwind utilities; `.env` and `.env.local` ignored, `.env.example` not ignored.
- Not yet verified: owner's Windows machine, GitHub Actions.

### Phase 0 amendments — owner decisions (2026-10-13)

**Changed**
- Joining flow fixed as account first, email confirmation, authenticated code redemption, then Admin approval (D-03); `PROJECT_SPEC.md` §5A, `SECURITY.md` §6, `PROJECT_STATE.md` and related sections made consistent.
- Decided: D-05, D-06, D-08, D-11, D-13. Added D-18 (spam-account mitigation). Added SEC-23 and SEC-24 to the test plan.

### Phase 0 — Documentation foundation (2026-10-12)

**Added**
- `PROJECT_SPEC.md` v1.1: product baseline from the owner's v1.0 spec, plus Superadmin, configurable organizational hierarchy, criteria IDs and three added Superadmin acceptance criteria.
- `PROJECT_STATE.md` with decision register (D-01 to D-17) and the exact next step.
- `IMPLEMENTATION_PLAN.md`: Phases 0–5, Phase 1 sub-steps, exit gates, Git checkpoints.
- `ARCHITECTURE.md`: system design, authorization layers, privileged-operation catalogue, realtime, PWA, notifications.
- `SECURITY.md`: threat model, RLS strategy, joining-code security, Superadmin bootstrap and recovery, secrets, audit, residual risks.
- `DATABASE.md`: proposed schema (not implemented), migration order.
- `TEST_PLAN.md`: strategy, persona-based RLS tests, criteria mapping, E2E flows.
- `AGENTS.md`: rules for AI-assisted development.
- `README.md`: overview, prerequisites, planned setup (commands labelled not yet usable).
- `.env.example`: placeholders only.

**Not done (by design)**
- No application code, dependencies, Supabase project, migrations, tests or deployment.

**Verification**
- Documents drafted; owner review and commit pending. No commands have been run against a repository.
