# PROJECT_STATE

Single source of truth for current progress. Update at the end of every phase and every meaningful session. Record only results that were actually observed.

**Last updated:** 2026-10-18 · **Current phase:** 2a built on top of 1a to 1e; **Phase 1 exit gate not met** (nothing verified by the owner or on Supabase) · **Repository:** https://github.com/MdSham1403/UAM-Connect

## Status summary

| Item | State |
|---|---|
| Repository created on GitHub | Done |
| Phase 0 documents | Drafted and amended; owner commit not confirmed in this session |
| Application code | Scaffold, authentication, join/waiting/approved/restricted screens, MFA setup, Administration (joining codes, requests, suspend/reinstate), **team directory with search, and operational-role administration (create, rename, deactivate, assign several roles per member with one primary)**. No shifts, availability or board. No screen for granting Team Lead or Admin |
| Supabase project(s) | None created. Owner creates the **development** project (README). No production project |
| Migrations | 5 written, **not applied to any Supabase project**: baseline, `profiles`, `membership`, `superadmin`, `operational_roles` |
| Frontend tests | 123 mocked tests (fake Supabase client). Sandbox run only |
| Database tests | `supabase/tests/verify.sql`, 329 checks, no Docker; also a CI `database` job (commands run locally; GitHub run not seen). Sandbox run on plain PostgreSQL 16 only |
| Deployment | None |

## Verification ledger (Phases 1a–1e)

Environment of every "verified" claim below: the assistant's Linux sandbox, Node v22.22.2, npm 10.9.7, PostgreSQL 16.15 with stub `anon`/`authenticated`/`service_role` roles and a stub `auth` schema (superuser owner). **Not** Windows, **not** GitHub Actions, **not** Supabase.

| Level | Status |
|---|---|
| Implemented | Yes: 1a scaffold, 1b baseline, 1c profiles and auth UI, 1d membership, 1e Superadmin migration, owner-only bootstrap function, reviewer read policies, MFA and Administration UI, runbook, CI database job, `verify.sql` |
| Scaffold checks (sandbox) | `typecheck`, `lint`, `format:check`, `test` (123 passed), `build` all exit 0 |
| Verified on a clean plain PostgreSQL 16 | All five migrations apply; `verify.sql` PASS 329/329 (also through `supabase db query --db-url`, and by the CI job's own commands). The runbook bootstrap sequence was run through the CLI: first run succeeds, second is refused, unconfirmed account refused, last-owner removal blocked. Planted flaws: 7 (1b-1c), 12 (1d) and 11 (1e: guard removed, bootstrap repeatable, Admin grants Admin, Admin suspends Superadmin, bootstrap grants Admin, open profile policy, readable code hash, bootstrap callable by clients, PUBLIC execute left open, suspended keep permissions, unscoped reviewer policy) were each caught; for 2a, 12 more (role creation without MFA, inactive or cross-team roles assignable, directory open to non-members or listing pending people, inactive roles shown to everyone, deletion cascading over history, several primaries, readable role tables, unassign without permission, PUBLIC execute left open, un-audited updates) and 5 broken UI behaviours were each caught. Two of my own new tests initially failed for the wrong reasons (assumed earlier state; a variable that did not exist) and a duplicate-HTML-id accessibility bug in the first version of the role form was found by a test; all fixed |
| Verified with the Supabase CLI, no Docker | `supabase db query --db-url` ran `verify.sql` against the local PostgreSQL. Config parses (valid config reaches the Docker check; a broken copy fails with a parse error) |
| Verified on the Supabase local stack | **No** (Docker not used or available) |
| Verified against a hosted dev project | **No.** No project exists. `db push --dry-run`, `db push`, `db query --linked` behaviour (including how the Management API returns the deliberate error), real Auth emails, PKCE, rate limits, `auth.users` fixtures in `verify.sql`, PostgREST behaviour for profile insert/update: all unverified |
| Mocked vs real | All frontend auth tests are **mocked**. No real-Supabase integration test exists; see [TEST_PLAN](TEST_PLAN.md) §10 |
| Not verified | The `aal` JWT claim, TOTP enrolment and the aal2 upgrade against real Supabase (the MFA UI is tested with mocks only); `auth.users` access from the function owner; running the bootstrap on Supabase (SQL editor or `db query --linked`); PostgreSQL 17 vs 16; GitHub Actions (including the new database job); Windows CMD behaviour; D-17 |
| Phase 1a acceptance | **Not confirmed by the owner** |
| Acceptance criteria (database level, sandbox) | AC-M1, AC-M2, AC-M3, AC-M6 as in 1d. AC-S8 (no path creates or promotes a Superadmin: privilege inventory, attempted writes, source-level scan, owner-only bootstrap). AC-S10 (last Superadmin cannot be removed: guard trigger). AC-S9 (recovery without the UI) only on plain PostgreSQL. AC-S1, S2, S3 partially (persona RLS matrix; no secret scan beyond the repository). **None verified end to end through the UI or against Supabase** |
| Provenance and recovery (2026-10-18) | Between the Phase 1d zip (2026-10-15) and this session, earlier work in the sandbox had added a Phase 1e backend and frontend that is not in any zip or in these documents: `src/features/admin`, `src/features/mfa`, a 252-check `verify.sql`, and a modification of the 0200 migration (explicit revoke note) and of `config.toml` (TOTP MFA on). **While starting this session I overwrote `20261013000300_superadmin.sql` with a different design before noticing that file already existed; the earlier text was not in Git or any zip and could not be recovered.** I rebuilt it to satisfy the surviving `verify.sql` and frontend (which define its interface exactly) and kept everything else untouched. The rebuilt migration may differ in details from the lost one (for example the override flag and truncate guard on `platform_owners` are mine). A pre-repair copy of the tree is at `/home/claude/backup/before_1e_repair` in the sandbox (not part of the zip). Review `20261013000300_superadmin.sql` yourself before applying it. Earlier correction: the Phase 1b instruction to run `supabase test db --linked` could not work without Docker |

## Completed

- GitHub repository created.
- Phase 1b baseline database and Phase 1c authentication (profiles migration, auth UI, tests) written; see ledger.
- Phase 0 documents drafted: `PROJECT_SPEC.md`, `PROJECT_STATE.md`, `IMPLEMENTATION_PLAN.md`, `ARCHITECTURE.md`, `SECURITY.md`, `DATABASE.md`, `TEST_PLAN.md`, `AGENTS.md`, `README.md`, `CHANGELOG.md`, `.env.example`.

## Not started

Everything in Phases 1–5 (see [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)).

## Known issues

None. No code exists. Documents have not yet had a consistency review by the owner.

## Decision register

Status: **Open** = needs owner decision; **Proposed** = default documented, awaiting confirmation. "Blocks" = the phase that cannot start safely without it.

| ID | Decision | Proposed default | Status | Blocks |
|---|---|---|---|---|
| D-01 | Superadmin bootstrap mechanism | **Implemented per the proposed default:** `platform_owners` (no API access) plus the owner-only `private.bootstrap_superadmin()` run from the SQL editor; recovery by re-running it with `recovery := true`; last-owner guard trigger. Awaiting your confirmation. See [SECURITY](SECURITY.md) §7 and [the runbook](docs/RUNBOOK_SUPERADMIN.md). | Implemented, **unconfirmed** | Phase 1 |
| D-02 | Joining-code design | **Implemented per the proposed default** (80-bit random code, SHA-256 hash stored, expiry, max uses, revocation, rate limit). Awaiting your confirmation. | Implemented, **unconfirmed** | Phase 1d |
| D-03 | Joining flow | **Decided 2026-10-13:** user creates an account, confirms email, redeems a joining code while authenticated, then awaits Admin approval. Redemption is an authenticated function; attempts are attributable and rate-limited. Spam-account mitigation tracked in D-18. | **Decided** | Phase 1 |
| D-04 | Frontend hosting provider | Any approved static host. Provider not chosen. | Open | Phase 5 |
| D-05 | Team Lead default permissions | **Decided 2026-10-13:** coordinate/assign/resolve incidents, publish announcements and knowledge. **No** member approvals or access administration (no role, shift or code management). | **Decided** | Phase 1 |
| D-06 | Role administration | **Decided 2026-10-13:** only Superadmin grants/revokes Admin; Admin grants Member and Team Lead. | **Decided** | Phase 1 |
| D-07 | Organizational hierarchy modelling | Free-text title now plus nullable `reports_to_membership_id`; no assumed relationships; configurable later. | Proposed | Phase 2 |
| D-08 | Supabase environments | **Decided 2026-10-13:** separate hosted development and production projects, migrations via Supabase CLI; local Docker optional initially. | **Decided** | Phase 1 |
| D-09 | Push sender | Supabase Edge Function holding the VAPID private key as a secret. Needs confirmation that Edge Functions are acceptable. iOS Web Push requires an installed PWA. | Proposed | Phase 5 |
| D-10 | Retention policy | Keep everything in v1 (archive flags, no hard deletes); audit log append-only. | Proposed | Phase 3 |
| D-11 | Team data | **Decided 2026-10-13:** synthetic data only until Supabase is explicitly approved for real team data; never real banking or company data before then. | **Decided** | Phase 1 |
| D-24 | Operational-role rules | Names unique per team across active and inactive roles; inactive roles hidden from members and blocked for new assignment; Team Lead cannot manage roles (D-05); role changes need MFA. Colour, icon, `can_coordinate` and per-shift coverage requirements deferred | Implemented as proposed, **unconfirmed** | Phase 2a |
| D-12 | Shift model details | Shift has time zone; assignments keyed by `work_date`; overnight shifts supported via `end_time < start_time`. | Proposed | Phase 2 |
| D-13 | Privileged actions | **Decided 2026-10-13:** require TOTP MFA (aal2) for sensitive Admin/Superadmin actions. Exact action list in [SECURITY](SECURITY.md) §10; Supabase MFA behaviour to be verified in Phase 1c/1e. | **Decided** | Phase 1 |
| D-14 | Incident reference format | `INC-0001` per team, generated inside the create function. | Proposed | Phase 3 |
| D-15 | Default severities | Low, Medium, High, Critical, stored in a table. | Proposed | Phase 3 |
| D-16 | Supported browsers/devices | Latest Chrome/Edge/Safari on Android/iOS/Windows; confirm the team's real devices. | Open | Phase 5 |
| D-17 | Package manager and Node version | npm; Node 22 (`.nvmrc`), `engines >=22.12.0` (Vitest/Vite requirement). | Proposed (implemented in 1a; confirm) | Phase 1 |
| D-19 | Hosted Auth settings and email templates | Apply README "Hosted Supabase Auth settings"; change confirm/reset templates to token-hash links so links work across devices. Hosted change: needs owner approval | Proposed | Real end-to-end auth testing |
| D-20 | Email delivery (SMTP provider) | Custom SMTP before real users; built-in sender is development only | Open | Before real users |
| D-21 | Failure caps for code redemption | 5 failures per user and 50 across all users per 15 minutes. The global cap lets any signed-in user block joining for 15 minutes (R-19); CAPTCHA or per-IP limits would reduce this | Proposed | Phase 1d |
| D-22 | Rejected applicants may re-apply with a new code; suspended and removed users may not | Implemented as proposed | Proposed | Phase 1d |
| D-23 | Reviewer reads (member names/titles, requests, code metadata) need no MFA; actions do | Implemented as proposed (R-22) | Proposed | Phase 1e |
| D-18 | Spam-account mitigation before code redemption | Email confirmation (decided with D-03) plus Supabase Auth rate limits; decide whether to add CAPTCHA and/or an email-domain allowlist. | Open | Phase 1d |

## Exact next step

1. **Read `supabase/migrations/20261013000300_superadmin.sql` yourself** (it was rebuilt; see the ledger row "Provenance and recovery"), and tell me if anything differs from what you expected.
2. Extract the Phase 1e zip over the repo (CMD: `tar -xf UAM-Connect-phase-1e.zip`), run `npm ci` and the five scaffold checks on Windows, and share the results. Push and share the result of the GitHub Actions run, including the new `database` job.
3. Create the Supabase **development** project; follow README through `db push --dry-run`, review, approve `db push`, then `npm run db:verify` (expect `PASS (329 passed, 0 failed)`).
4. Sign up in the app with your own email, confirm it, then follow [docs/RUNBOOK_SUPERADMIN.md](docs/RUNBOOK_SUPERADMIN.md) to bootstrap the Superadmin, set up MFA, and run the manual checklist in TEST_PLAN §10 (items 1-15).
5. Decide D-18 and D-19, confirm D-01, D-02, D-17, D-21, D-22, D-23.

**Phase 1 is not complete until steps 2-4 pass on a real Supabase project.** Phase 2a (operational roles and directory) was built at your request before that gate; it adds one migration (`20261013000400_operational_roles.sql`, read it too) and should be verified together with the rest. Phase 2b (shifts, availability) and 2c (Live Ops Board, Realtime, optional reporting line D-07) have not started.
