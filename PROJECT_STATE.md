# PROJECT_STATE

Single source of truth for current progress. Update at the end of every phase and every meaningful session. Record only results that were actually observed.

**Last updated:** 2026-10-12 · **Current phase:** 0 (documentation) · **Repository:** https://github.com/MdSham1403/UAM-Connect

## Status summary

| Item | State |
|---|---|
| Repository created on GitHub | Done |
| Phase 0 documents drafted | Drafted; **not yet reviewed or committed by the owner** |
| Application code | Not started (none exists) |
| Supabase project(s) | Not created |
| Migrations | None |
| Automated tests | None; nothing has been run |
| Deployment | None |

## Completed

- GitHub repository created.
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
| D-03 | Signup order: account first, or code first | Account (email-confirmed) first, then code redemption through an authenticated function so attempts are attributable and rate-limited. Consider CAPTCHA and/or email-domain allowlist to limit spam accounts. | Open | Phase 1 |
| D-04 | Frontend hosting provider | Any approved static host. Provider not chosen. | Open | Phase 5 |
| D-05 | Team Lead default permissions | Coordinate/assign/resolve incidents, publish announcements and knowledge. **No** member approval, role, shift or code management. | Proposed | Phase 1 |
| D-06 | Who may grant Admin | Only Superadmin grants/revokes Admin; Admins grant Member/Team Lead. | Proposed | Phase 1 |
| D-07 | Organizational hierarchy modelling | Free-text title now plus nullable `reports_to_membership_id`; no assumed relationships; configurable later. | Proposed | Phase 2 |
| D-08 | Supabase environments | Separate hosted dev and production projects, migrations via Supabase CLI; local Docker stack optional but recommended for RLS tests. | Open | Phase 1 |
| D-09 | Push sender | Supabase Edge Function holding the VAPID private key as a secret. Needs confirmation that Edge Functions are acceptable. iOS Web Push requires an installed PWA. | Proposed | Phase 5 |
| D-10 | Retention policy | Keep everything in v1 (archive flags, no hard deletes); audit log append-only. | Proposed | Phase 3 |
| D-11 | Data classification and approved hosting | Confirm Supabase is approved for team data. Until confirmed, use synthetic data only; never real banking or company data. | Open | Phase 1 |
| D-12 | Shift model details | Shift has time zone; assignments keyed by `work_date`; overnight shifts supported via `end_time < start_time`. | Proposed | Phase 2 |
| D-13 | MFA for privileged users | Require TOTP MFA (aal2) for Admin/Superadmin actions where Supabase supports it. | Open | Phase 1 |
| D-14 | Incident reference format | `INC-0001` per team, generated inside the create function. | Proposed | Phase 3 |
| D-15 | Default severities | Low, Medium, High, Critical, stored in a table. | Proposed | Phase 3 |
| D-16 | Supported browsers/devices | Latest Chrome/Edge/Safari on Android/iOS/Windows; confirm the team's real devices. | Open | Phase 5 |
| D-17 | Package manager and Node version | npm; current Node LTS pinned in Phase 1. | Proposed | Phase 1 |

## Exact next step

1. Review the Phase 0 documents; note any contradictions with your intent.
2. Copy them into the repository root, inspect `git status`, and commit Phase 0.
3. Reply with decisions for **D-03, D-08, D-11 and D-13** (confirm or change the others' proposed defaults), then explicitly ask to begin **Phase 1a**.

Do not start Phase 1 before step 3.
