# CHANGELOG

All notable changes by phase. Format loosely follows Keep a Changelog. Test and build results appear here only when they were actually run.

## [Unreleased]

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
