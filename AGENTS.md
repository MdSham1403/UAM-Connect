# AGENTS

Rules for any AI assistant or coding agent working on UAM Connect. Read this file fully before every session.

## Before changing anything

1. Read [PROJECT_SPEC](PROJECT_SPEC.md) in full and [PROJECT_STATE](PROJECT_STATE.md) for the current phase and exact next step.
2. Read the relevant parts of [IMPLEMENTATION_PLAN](IMPLEMENTATION_PLAN.md), [ARCHITECTURE](ARCHITECTURE.md), [DATABASE](DATABASE.md), [SECURITY](SECURITY.md) and [TEST_PLAN](TEST_PLAN.md).
3. Inspect the repository (`git status`, existing files, installed tooling). Do not assume.
4. If `PROJECT_SPEC.md` or `PROJECT_STATE.md` is missing or contradicts the request, stop and report. Do not invent a replacement.

## Scope and discipline

- Work on **one phase and one sub-step at a time**. Never start the next phase without the owner's explicit approval.
- Make the smallest change that meets the acceptance criteria. Edit with targeted patches; do not regenerate whole files or rewrite unrelated files.
- Preserve existing work. Do not delete or overwrite files or configuration without stating why.
- Do not add dependencies or infrastructure without a written justification (what, why, alternatives). No separate backend, Redis or extra services without a documented requirement.
- If a detail is unspecified, record a proposed default and mark the decision in [PROJECT_STATE](PROJECT_STATE.md). Do not silently decide security-relevant questions.

## Architecture rules (non-negotiable)

- Organizational title, operational roles and application permissions are separate concepts. Never derive permissions from title or operational role.
- Superadmin is never granted by public signup, a joining code, a profile field, a client-side email check or any self-assignment. See [SECURITY](SECURITY.md) §7.
- Every protected table has RLS and tests. Client-side visibility is never the only control.
- Privileged changes go through narrowly scoped database functions with internal checks and audit entries.
- Schema changes only through versioned migrations; never edit an applied migration, add a new one.
- Joining codes are hashed, expiring, revocable and rate-limited.

## Secrets and data

- Never commit secrets, `.env` files or real credentials. Only `.env.example` with placeholders.
- Never place the service-role key, VAPID private key or any server secret in frontend code, `VITE_` variables, logs, prompts or chat.
- Never invent Supabase project IDs, owner identities, keys or URLs; use placeholders.
- Use synthetic data only. No real banking or company data in unapproved environments.

## Verification

- Run the relevant checks (typecheck, lint, tests, build, migration check) and **report the actual commands and real output**.
- Never claim a test, build or deployment passed unless it was executed and the result observed. If something could not be run, say so.
- Review your own diff for unrelated changes, insecure policies, hardcoded secrets and missing error states before reporting.
- Security failures block the phase gate.

## Reporting (end of every task)

1. Files created, modified or deleted (and why for any deletion).
2. Decisions made or proposed.
3. Commands run and actual results.
4. Security risks and unresolved decisions.
5. Whether [PROJECT_STATE](PROJECT_STATE.md) and [CHANGELOG](CHANGELOG.md) were updated.
6. The exact next step, then **stop and wait for approval**.

## Conventions

- TypeScript strict mode; no `any` without a comment explaining why.
- Feature folders under `src/features/`; shared primitives in `src/components/ui/`; typed Supabase access through `src/lib/`.
- Every screen defines loading, empty, error and retry states; mobile-first layouts.
- Commit messages: conventional style (`feat(scope): …`, `fix`, `docs`, `chore`, `test`), one logical change per commit, tag at each phase exit.
- Windows + VS Code is the owner's environment: give PowerShell-compatible commands.
- Owner constraints: limited AI usage, so avoid repeated work, keep explanations short, and provide copy-ready content when direct file access is unavailable.
