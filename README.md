# UAM Connect

A private, mobile-first Progressive Web App for a team of about 15–18 User Access Management (UAM) members: a coordination and continuity workspace showing who is available, who owns what, what is happening, and what must be handed over. It complements Sapphire, Microsoft Teams and WhatsApp; it does not replace them.

> **Status: Phase 2a — operational roles and team directory (on top of Phase 1e administration).** Sign-up with email confirmation, sign-in/out, password recovery, a join screen, and now an Administration section for Admins and the Superadmin (authenticator-app MFA setup, joining codes, approve or reject requests, suspend or reinstate members). The Superadmin is created once by the project owner with a database function (see [docs/RUNBOOK_SUPERADMIN.md](docs/RUNBOOK_SUPERADMIN.md)); no screen can create one. Approved members get a searchable team directory. Admins and the Superadmin can create, rename, deactivate and assign operational roles (BAU / Ticketing, Queue Manager, Onboarding, Resignation, Retain, Reconciliation are seeded). There is still no screen for granting Team Lead or Admin (the database functions exist); shifts, availability and the Live Ops Board are not built yet. Signing in never gives access to team information. **Nothing has been verified against a real Supabase project yet.**

## Planned stack

React + TypeScript + Vite · Tailwind CSS · Supabase (Auth, PostgreSQL, Realtime) · PostgreSQL Row Level Security · PWA + service worker · Web Push (later) · Vitest, React Testing Library, Playwright · Git/GitHub. **Docker is not required.**

## Documentation

| Document | Purpose |
|---|---|
| [PROJECT_SPEC.md](PROJECT_SPEC.md) | Product requirements, permissions, workflows, acceptance criteria |
| [PROJECT_STATE.md](PROJECT_STATE.md) | Current progress, verification ledger, decision register, exact next step |
| [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) | Phases, dependencies, exit gates, Git checkpoints |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Technical design and data flow |
| [DATABASE.md](DATABASE.md) | Schema: implemented parts and proposals |
| [SECURITY.md](SECURITY.md) | Threat model, RLS strategy, auth notes, Superadmin bootstrap, secrets |
| [docs/RUNBOOK_SUPERADMIN.md](docs/RUNBOOK_SUPERADMIN.md) | Superadmin bootstrap and recovery procedure |
| [TEST_PLAN.md](TEST_PLAN.md) | Test strategy, security tests, manual checklist |
| [AGENTS.md](AGENTS.md) | Rules for AI-assisted development |
| [CHANGELOG.md](CHANGELOG.md) | Changes by phase |

## Prerequisites (Windows, Command Prompt)

- Git, VS Code, and Node.js 22.12 or newer with npm (`.nvmrc` pins 22).
- A Supabase account (separate hosted development and production projects; D-08). Only the **development** project is used now.

```bat
git --version
node --version
npm --version
```

## Get the code and run the checks

```bat
git clone https://github.com/MdSham1403/UAM-Connect.git
cd UAM-Connect
npm ci
npm run typecheck
npm run lint
npm run format:check
npm run test
npm run build
```

## Run the app

The app needs your development project's **public** values. Create the local file and edit it in VS Code:

```bat
copy .env.example .env.local
code .env.local
```

| Variable | Value | Public? |
|---|---|---|
| `VITE_SUPABASE_URL` | Project URL from the Supabase dashboard | Yes |
| `VITE_SUPABASE_ANON_KEY` | The **anon/publishable** key only | Yes (protected by RLS) |
| Service-role key, secret keys, database password | Never in this file, in Git, or in chat | **No** |

The app refuses to start if the key looks like a service-role or secret key. `.env.local` is git-ignored. Then:

```bat
npm run dev
```

Without `.env.local` the app shows a clear configuration message instead of crashing.

## Scripts

```bat
npm run dev            # start dev server
npm run typecheck      # TypeScript check
npm run lint           # oxlint (includes a no-console rule so tokens are never logged)
npm run format         # Prettier (writes)
npm run format:check   # Prettier (check only)
npm run test           # Vitest + React Testing Library (mocked Supabase)
npm run build          # production build
npm run db:verify      # database verification against the LINKED dev project (no Docker)
```

`npm run db:start|db:stop|db:reset` use Docker and are optional; ignore them. `npm run test:e2e` (Playwright) is **[NOT YET USABLE: Phase 5]**.

## Supabase development workflow (no Docker)

Migrations are in `supabase/migrations/`, the synthetic seed in `supabase/seed.sql`, the database verification in `supabase/tests/verify.sql`. The Supabase CLI is a pinned dev dependency (`npx supabase ...`). Never paste tokens, passwords or keys into chat or Git.

**Steps you perform yourself:**

1. In the Supabase dashboard create a **development** project. Set a strong database password and keep it only in your password manager. Note the project's reference ID (Project Settings, General).
2. Log in (opens a browser; the token is kept by the CLI, not in the repo):
```bat
npx supabase login
```
3. Link the project; enter the database password at the prompt if asked:
```bat
npx supabase link --project-ref <YOUR_DEV_PROJECT_REF>
```
4. **Dry run.** This only lists what would be applied; it changes nothing:
```bat
npx supabase db push --dry-run
```
Expected: five pending migrations, `20261013000000_baseline_teams_audit.sql`, `20261013000100_profiles.sql`, `20261013000200_membership.sql` and `20261013000300_superadmin.sql` and `20261013000400_operational_roles.sql`. Together they create a `private` schema (helpers; API clients get usage only so a policy can call one helper), the tables `teams`, `audit_logs` (append-only), `profiles`, `team_memberships`, `app_roles`, `member_app_roles`, `join_codes`, `join_requests` and `rate_limit_events`, row level security on all of them, a few narrow read policies, and eight server functions for joining, approval, suspension and role changes that only signed-in users may call. They create no users and no data (Superadmin is created later by the bootstrap step in the runbook). The fifth adds operational roles and the directory functions. The fourth adds the `platform_owners` table (Superadmin), the owner-only bootstrap function, reviewer read policies and Admin-management rules. Review the third and fourth files in VS Code before approving.
5. **Apply only after you have reviewed step 4 and approve:**
```bat
npx supabase db push
```
6. Verify. This runs 329 checks inside a transaction that is always rolled back. The CLI prints "failed to execute query" on purpose; read the first line of the message and expect `VERIFY RESULT: PASS (329 passed, 0 failed)`:
```bat
npm run db:verify
```
If the CLI cannot run it, paste `supabase/tests/verify.sql` into the dashboard SQL editor instead.
7. Add the synthetic dev team (the bootstrap needs a team to exist). `db push` never applies the seed by itself:
```bat
npx supabase db query --linked -f supabase\seed.sql
```

8. **Bootstrap the Superadmin** (once): sign up in the app with your own email and confirm it, then follow [docs/RUNBOOK_SUPERADMIN.md](docs/RUNBOOK_SUPERADMIN.md).

Never run `supabase db reset --linked`, and never link a production project in this phase.

## Hosted Supabase Auth settings to review (recommended, not yet applied)

The local `supabase/config.toml` holds the recommended values, but it does **not** change your hosted project. Review these in the dashboard (Authentication) and apply them only when you approve:

- Email provider on, **Confirm email on**, minimum password length **12**, require lower-case, upper-case and digits, secure password change on.
- URL Configuration: Site URL `http://localhost:5173` for development, and add `http://localhost:5173/**` to the redirect allow-list.
- Optional but recommended for phones: change the **Confirm signup** and **Reset password** email templates to token-hash links so a link works on a different device than the one that started the flow (D-19):
  - confirm: `{{ .SiteURL }}/?flow=confirm&token_hash={{ .TokenHash }}&type=email`
  - reset: `{{ .SiteURL }}/?flow=recovery&token_hash={{ .TokenHash }}&type=recovery`
- The built-in email sender has very low limits and is for development only; choose a real SMTP provider before real use (D-20).
- CAPTCHA and email-domain allowlist are an open decision (D-18).

## Planned repository layout

```
src/            application code (features/auth, features/profile, lib, test helpers)
supabase/       config, migrations, seed, verify.sql
.github/        CI workflow
*.md            project documents
```

## Contributing workflow

One phase and one sub-step at a time; check the exit gate; commit; update `PROJECT_STATE.md`. See [IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) and [AGENTS.md](AGENTS.md).
