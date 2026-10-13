# PROJECT_STATE

Single source of truth for current progress. Update at the end of every phase and every meaningful session. Record only results that were actually observed.

**Last updated:** 2026-10-13 · **Current phase:** 1 (sub-step 1b built; 1a and 1b both await owner verification) · **Repository:** https://github.com/MdSham1403/UAM-Connect

## Status summary

| Item | State |
|---|---|
| Repository created on GitHub | Done |
| Phase 0 documents drafted | Drafted and amended 2026-10-13 with owner decisions; owner commit not confirmed in this session |
| Application code | Phase 1a scaffold built (app shell only, no features). Verified in the assistant's Linux sandbox only; **not yet run on the owner's machine or in GitHub Actions** |
| Supabase project(s) | None created by the assistant. Owner must create the **development** project and link the CLI (README, "Supabase development workflow"). No production project |
| Migrations | 1 baseline migration implemented (`teams`, `audit_logs`, `private` helpers). See verification ledger below |
| Automated tests | 1 smoke test. In the sandbox (Node v22.22.2, npm 10.9.7): typecheck, lint (oxlint), format:check, test (1 passed) and build all exited 0. Not yet run on the owner's machine or CI |
| Database tests | 35 pgTAP assertions in `supabase/tests/database/`. See ledger |
| Deployment | None |

## Phase 1b verification ledger

| Level | Status |
|---|---|
| Implemented | Yes: migration, seed, pgTAP tests, `db:*` scripts, `supabase/config.toml` |
| Locally verified (sandbox) | Config parses (valid file reaches the Docker check; a deliberately broken copy fails with a parse error). Scaffold checks `typecheck`, `lint`, `format:check`, `test`, `build` rerun after the change (see CHANGELOG) |
| Verified against a clean database | **Partially.** Applied to a clean **plain PostgreSQL 16.15 with stub `anon`/`authenticated`/`service_role` roles** (superuser owner), not the Supabase local stack: migration applied, 35/35 pgTAP assertions passed, seed applied three times leaving exactly one row. Mutation checks confirmed the tests fail when revokes, audit triggers or RLS are removed |
| Verified on the Supabase local stack | **No.** No Docker in the sandbox; `supabase start`, `db reset` and `db test` have not been run |
| Verified against the linked dev project | **No.** No project exists or is linked |
| Not verified | Behaviour under real Supabase roles/ownership/extensions; PostgreSQL 17 vs 16 differences; CI database job (not wired) |
| Phase 1a acceptance | **Not confirmed by the owner** (no Windows or GitHub Actions results received). 1b does not depend on it at runtime |

## Completed

- GitHub repository created.
- Phase 1b baseline database (migration, seed, tests) written; see ledger.
- Phase 0 documents drafted: `PROJECT_SPEC.md`, `PROJECT_STATE.md`, `IMPLEMENTATION_PLAN.md`, `ARCHITECTURE.md`, `SECURITY.md`, `DATABASE.md`, `TEST_PLAN.md`, `AGENTS.md`, `README.md`, `CHANGELOG.md`, `.env.example`.

## Not started

Everything in Phases 1–5 (see [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md)).

## Known issues

None. No code exists. Documents have not yet had a consistency review by the owner.

## Decision register

Status: **Open** = needs owner decision; **Proposed** = default documented, awaiting confirmation. "Blocks" = the phase that cannot start safely without it.

| ID | Decision | Proposed default | Status | Blocks |
|---|---|---|---|---|
| D-01 | Superadmin bootstrap mechanism | `platform_owners` table with no client write access; owner signs up normally, then runs a one-time documented SQL script in the Supabase SQL editor (trusted environment). See [SECURITY](SECURITY.md) §7. | Proposed | Phase 1 |
| D-02 | Joining-code design | High-entropy random code (at least 64 bits), stored as hash, expiry + max uses + revocation, attempts logged in `rate_limit_events`. | Proposed | Phase 1 |
| D-03 | Joining flow | **Decided 2026-10-13:** user creates an account, confirms email, redeems a joining code while authenticated, then awaits Admin approval. Redemption is an authenticated function; attempts are attributable and rate-limited. Spam-account mitigation tracked in D-18. | **Decided** | Phase 1 |
| D-04 | Frontend hosting provider | Any approved static host. Provider not chosen. | Open | Phase 5 |
| D-05 | Team Lead default permissions | **Decided 2026-10-13:** coordinate/assign/resolve incidents, publish announcements and knowledge. **No** member approvals or access administration (no role, shift or code management). | **Decided** | Phase 1 |
| D-06 | Role administration | **Decided 2026-10-13:** only Superadmin grants/revokes Admin; Admin grants Member and Team Lead. | **Decided** | Phase 1 |
| D-07 | Organizational hierarchy modelling | Free-text title now plus nullable `reports_to_membership_id`; no assumed relationships; configurable later. | Proposed | Phase 2 |
| D-08 | Supabase environments | **Decided 2026-10-13:** separate hosted development and production projects, migrations via Supabase CLI; local Docker optional initially. | **Decided** | Phase 1 |
| D-09 | Push sender | Supabase Edge Function holding the VAPID private key as a secret. Needs confirmation that Edge Functions are acceptable. iOS Web Push requires an installed PWA. | Proposed | Phase 5 |
| D-10 | Retention policy | Keep everything in v1 (archive flags, no hard deletes); audit log append-only. | Proposed | Phase 3 |
| D-11 | Team data | **Decided 2026-10-13:** synthetic data only until Supabase is explicitly approved for real team data; never real banking or company data before then. | **Decided** | Phase 1 |
| D-12 | Shift model details | Shift has time zone; assignments keyed by `work_date`; overnight shifts supported via `end_time < start_time`. | Proposed | Phase 2 |
| D-13 | Privileged actions | **Decided 2026-10-13:** require TOTP MFA (aal2) for sensitive Admin/Superadmin actions. Exact action list in [SECURITY](SECURITY.md) §10; Supabase MFA behaviour to be verified in Phase 1c/1e. | **Decided** | Phase 1 |
| D-14 | Incident reference format | `INC-0001` per team, generated inside the create function. | Proposed | Phase 3 |
| D-15 | Default severities | Low, Medium, High, Critical, stored in a table. | Proposed | Phase 3 |
| D-16 | Supported browsers/devices | Latest Chrome/Edge/Safari on Android/iOS/Windows; confirm the team's real devices. | Open | Phase 5 |
| D-17 | Package manager and Node version | npm; Node 22 (`.nvmrc`), `engines >=22.12.0` (Vitest/Vite requirement). | Proposed (implemented in 1a; confirm) | Phase 1 |
| D-18 | Spam-account mitigation before code redemption | Email confirmation (decided with D-03) plus Supabase Auth rate limits; decide whether to add CAPTCHA and/or an email-domain allowlist. | Open | Phase 1d |

## Exact next step

1. Owner confirms 1a: runs the 1a checks on Windows and confirms the GitHub Actions run is green (still outstanding).
2. Owner applies the Phase 1b changes, runs `npm ci`, the scaffold checks, and (with Docker Desktop) `npm run db:start`, `npm run db:reset`, `npm run db:test`; shares real output.
3. Owner creates the Supabase **development** project, links the CLI, runs `db push --dry-run` then `db push`, and runs `db test --linked` (README). Shares output without secrets.
4. Review 1b. Before 1c: nothing new is blocking. Before 1d: decide D-18 and confirm D-01, D-02, D-17.
