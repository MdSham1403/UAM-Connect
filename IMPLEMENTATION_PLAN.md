# IMPLEMENTATION_PLAN

Small, verifiable phases. Each sub-step ends in a Git commit. No phase starts until the previous exit gate is reviewed and the owner says to continue. No durations are promised.

Acceptance IDs (AC-xx) are defined in [PROJECT_SPEC](PROJECT_SPEC.md) §7; test methods in [TEST_PLAN](TEST_PLAN.md); open decisions (D-xx) in [PROJECT_STATE](PROJECT_STATE.md).

## Dependency overview

```
Phase 0 docs
   └─> Phase 1 (scaffold, auth, membership, RLS, Superadmin)
          └─> Phase 2 (roles, shifts, availability, Live Ops Board)
                 └─> Phase 3 (incidents, help, announcements, in-app notifications)
                        └─> Phase 4 (handovers, knowledge)
                               └─> Phase 5 (PWA, push, E2E, deployment, recovery)
```

Cross-cutting from Phase 1: every new table ships with RLS, policies, and tests in the same commit as the migration. Security criteria are acceptance criteria, not follow-up work.

## Phase 0 — Documentation

**Objective:** documentation, architecture, security plan, acceptance criteria.
**Deliverables:** the ten required documents and `.env.example`.
**Acceptance:** all files exist; no contradictions with [PROJECT_SPEC](PROJECT_SPEC.md); unresolved decisions listed; trusted Superadmin bootstrap proposed; owner has reviewed.
**Checkpoint:** `docs: Phase 0 documentation foundation`, tag `phase-0`.

## Phase 1 — Secure foundation

**Prerequisites:** D-03, D-08, D-11, D-13 decided; D-01/D-02/D-05/D-06 confirmed.

| Step | Work | Acceptance | Commit |
|---|---|---|---|
| 1a | Vite + React + TypeScript scaffold, Tailwind, Vitest + RTL, ESLint, Prettier, `.gitignore` (verify `.env*` ignored), CI workflow running typecheck/lint/test/build | App shell renders; `typecheck`, `lint`, `test`, `build` pass locally and in CI; fresh clone runs from README | `chore: scaffold app` |
| 1b | Supabase dev project, CLI linked, baseline migration (`teams`, helper functions, audit table), seed one team | Migrations apply from empty database (AC-S6 start); no secrets in Git | `feat(db): baseline migration` |
| 1c | Auth: sign-in/out, recovery, session handling, `profiles` | User can sign up, confirm, sign in, sign out; session expiry handled | `feat(auth): authentication` |
| 1d | Joining codes, `redeem_join_code`, pending membership, admin approve/reject/suspend functions, audit entries | AC-M1, AC-M2, AC-M3, AC-M6 verified by tests | `feat(membership): codes and approval` |
| 1e | Superadmin bootstrap script + runbook, application permission bundles, minimal admin Members screen, RLS test suite for all personas | AC-S1, AC-S2, AC-S3, AC-S8, AC-S9, AC-S10 verified; bootstrap executed once and documented | `feat(security): superadmin and rls tests` |

**Exit gate:** unauthorized users cannot access team data; Admin can approve a member safely; Superadmin bootstrap verified and recovery runbook exercised.
**Tag:** `phase-1`.

## Phase 2 — Team and Live Ops Board

**Depends on:** Phase 1.
Work: operational roles (admin CRUD, deactivate, assign, multiple per member, primary flag), organizational title and optional reporting line (D-07), team directory and profiles, shift definitions and assignments, availability with expiry (effective status computed at read time), Live Ops Board with coverage and gaps, Realtime subscription for board data.
**Acceptance:** AC-M4, AC-M5, AC-L1, AC-L2, AC-L3, AC-L5; AC-L4 (shift/coverage part; incident part completes in Phase 3); AC-S5 checked on narrow screens.
**Exit gate:** members see accurate shared status and coverage on mobile.
**Checkpoints:** `feat(roles)`, `feat(shifts)`, `feat(live-board)`; tag `phase-2`.

## Phase 3 — Coordination

**Depends on:** Phase 2 (roles, memberships, board).
Work: severities, incidents (create, claim, assign, update timeline, resolve/reopen with reason), help requests with volunteers and conditional confirmation, announcements with pin/expiry/acknowledgement, in-app notifications (database-generated), rate limits on creation actions.
**Acceptance:** AC-I1 to AC-I5, AC-H1, AC-H2, AC-H5 (announcements), AC-N1, AC-L4 (incident part).
**Exit gate:** a complete simulated outage can be coordinated from report to resolution.
**Checkpoints:** `feat(incidents)`, `feat(help-requests)`, `feat(announcements)`, `feat(notifications)`; tag `phase-3`.

## Phase 4 — Continuity

**Depends on:** Phase 3 (incidents, help requests, memberships).
Work: handovers and items (submit does not complete items; receiver acknowledgement), unresolved-items view, knowledge drafts/publish/revisions, full-text search.
**Acceptance:** AC-H3, AC-H4, AC-H5 (handovers), AC-N4, AC-N5.
**Exit gate:** an incoming member can understand and continue unresolved work without private messages.
**Checkpoints:** `feat(handover)`, `feat(knowledge)`; tag `phase-4`.

## Phase 5 — Release

**Depends on:** Phases 1–4; D-04, D-09, D-16 decided.
Work: manifest and service worker, install flow, Web Push (subscription, Edge Function sender, generic payloads), Playwright E2E for key flows, full security regression, production Supabase project and hosting, backup and recovery documentation, admin onboarding guide.
**Acceptance:** AC-N2, AC-N3, AC-S4, AC-S5, AC-S6, AC-S7; re-verification of AC-S1, S2, S3, S8, S9, S10 on the production configuration.
**Exit gate:** all release-blocking checks pass, production configured, team can use the application.
**Checkpoints:** `feat(pwa)`, `feat(push)`, `test(e2e)`, `docs(release)`; tag `v1.0.0` only after the gate.

## Per-phase working loop

1. State objective and acceptance criteria. 2. List files to be created/changed. 3. Smallest practical implementation. 4. Run checks and record actual output. 5. Review diff for unrelated rewrites, insecure policies, hardcoded secrets. 6. Update [PROJECT_STATE](PROJECT_STATE.md) and [CHANGELOG](CHANGELOG.md). 7. Commit. 8. Owner approval before the next step.

## Risks to the plan

- Open decisions block Phase 1 start (listed above).
- RLS design is the hardest part; it is front-loaded into Phase 1 deliberately.
- Web Push on iOS and hosting/approval constraints are unknown until Phase 5; spike early if the team relies on push.
