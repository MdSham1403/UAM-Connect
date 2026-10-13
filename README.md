# UAM Connect

A private, mobile-first Progressive Web App for a team of about 15–18 User Access Management (UAM) members: a coordination and continuity workspace showing who is available, who owns what, what is happening, and what must be handed over. It complements Sapphire, Microsoft Teams and WhatsApp; it does not replace them.

> **Status: Phase 1b — database foundation.** App shell, Tailwind, Vitest, CI, Supabase CLI config, a baseline migration and database tests exist. The app does not connect to Supabase yet; there is no authentication or feature code. Commands marked **[NOT YET USABLE]** work only after the phase noted.

## Planned stack

React + TypeScript + Vite · Tailwind CSS · Supabase (Auth, PostgreSQL, Realtime) · PostgreSQL Row Level Security · PWA + service worker · Web Push (later) · Vitest, React Testing Library, Playwright · Git/GitHub.

## Documentation

| Document | Purpose |
|---|---|
| [PROJECT_SPEC.md](PROJECT_SPEC.md) | Product requirements, permissions, workflows, acceptance criteria |
| [PROJECT_STATE.md](PROJECT_STATE.md) | Current progress, decision register, exact next step |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Phases, dependencies, exit gates, Git checkpoints |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Technical design and data flow |
| [DATABASE.md](DATABASE.md) | Proposed schema (not yet implemented) |
| [SECURITY.md](SECURITY.md) | Threat model, RLS strategy, Superadmin bootstrap, secrets |
| [TEST_PLAN.md](TEST_PLAN.md) | Test strategy and security test cases |
| [AGENTS.md](AGENTS.md) | Rules for AI-assisted development |
| [CHANGELOG.md](CHANGELOG.md) | Changes by phase |

## Prerequisites (Windows)

- Git and a GitHub account.
- Node.js 22.12 or newer (`.nvmrc` pins 22; Vitest and Vite require it) and npm.
- VS Code.
- A Supabase account (separate hosted development and production projects; D-08). Docker Desktop and the Supabase CLI are optional until local database testing is chosen.
- A modern browser; a real phone for PWA and push testing in Phase 5.

Check what you have (works today):

```powershell
git --version
node --version
npm --version
```

## Get the repository

```powershell
git clone https://github.com/MdSham1403/UAM-Connect.git
cd UAM-Connect
```

## Local setup

```powershell
npm install
Copy-Item .env.example .env.local
# .env.local is not read by the app until Phase 1b; Supabase values are added then
npm run dev
```

## Environment configuration

Copy `.env.example` to `.env.local` (git-ignored). Never commit real values.

| Variable | Where | Public? |
|---|---|---|
| `VITE_SUPABASE_URL` | Frontend | Yes (project URL) |
| `VITE_SUPABASE_ANON_KEY` | Frontend | Yes (anon/publishable key; protected by RLS) |
| `VITE_VAPID_PUBLIC_KEY` | Frontend (Phase 5) | Yes |
| Service-role key, VAPID private key | Supabase function secrets only | **Never** in frontend, Git or chat |

## Scripts

```powershell
npm run dev          # start dev server
npm run typecheck    # TypeScript check
npm run lint         # oxlint (create-vite default)
npm run format       # Prettier (writes)
npm run format:check # Prettier (check only)
npm run test         # Vitest + React Testing Library
npm run build        # production build
```

`npm run test:e2e` (Playwright) is **[NOT YET USABLE: Phase 5]**.

Database and RLS tests are defined in Phase 1 ([TEST_PLAN.md](TEST_PLAN.md)).

## Supabase development workflow (Phase 1b)

Migrations live in `supabase/migrations/`, the synthetic seed in `supabase/seed.sql`, database tests in `supabase/tests/database/`. The Supabase CLI is a pinned dev dependency (`npx supabase ...`). Use **development** only; never link production in this phase. Never paste tokens, passwords or keys into chat or Git.

**A. Local stack (needs Docker Desktop):**
```powershell
npm run db:start    # starts the local Supabase stack
npm run db:reset    # drops and rebuilds the local DB from migrations, then runs the seed
npm run db:test     # runs pgTAP tests against the local DB
npm run db:stop
```

**B. Hosted development project (you do these steps yourself):**
1. In the Supabase dashboard create a new **development** project. Set a strong database password and store it in your password manager only. Copy the project reference from the project's settings.
2. `npx supabase login` (opens a browser; the token is kept by the CLI, not in the repo).
3. Link, entering the database password at the prompt:
```powershell
npx supabase link --project-ref <YOUR_DEV_PROJECT_REF>
```
4. Preview, then apply the migration (never pass `--include-seed` unless you want the synthetic team in the dev project; never use `db reset --linked`):
```powershell
npx supabase db push --dry-run
npx supabase db push
npx supabase test db --linked
```
Link state is stored in `supabase/.temp/`, which Git ignores. `.env.local` is not needed for this phase.

## Planned repository layout

```
src/            application code
.github/        CI workflow
supabase/       config, migrations, seed, pgTAP tests (functions later)
docs/           runbooks: bootstrap, recovery, deployment (Phase 1 and 5)
*.md            project documents (this phase)
```

## Contributing workflow

One phase and one sub-step at a time; check the exit gate; commit; update `PROJECT_STATE.md`. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) and [AGENTS.md](AGENTS.md).

## Troubleshooting

Populated as problems are encountered after Phase 1. Until then, there is nothing to run.
