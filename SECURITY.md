# SECURITY

Status: **design and requirements**; no control is implemented yet. Enabling RLS is not proof of security: policies and privileged workflows must be tested ([TEST_PLAN](TEST_PLAN.md)). Related: [PROJECT_SPEC](PROJECT_SPEC.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DATABASE](DATABASE.md).

## 1. Assets and actors

**Assets:** team membership and identities; availability and incident information; announcements, handovers, knowledge notes; join codes; audit history; push subscriptions; Superadmin/Admin privileges; service-role and VAPID secrets.

**Actors:** anonymous visitor, pending member, approved Member, Team Lead, Admin, Superadmin, suspended/removed member, member of another team (future), malicious insider, external attacker.

**Data policy:** no banking credentials, access secrets, passwords, tokens, private keys or confidential customer data in the application. Use synthetic data until hosting is approved (D-11).

## 2. Trust boundaries

Browser (untrusted) → Supabase API (authenticated by JWT) → PostgreSQL (trusted; authority) and Edge Function (trusted; holds secrets). Everything the browser sends is untrusted input.

## 3. Roles and least privilege

| Role | Basis | Summary of access |
|---|---|---|
| Anonymous | none | Login/signup only; no table access |
| Pending | membership `pending` | Own join request and profile only |
| Member | approved | Read team data; manage own availability, profile, drafts; create incidents/help requests |
| Team Lead | app role | Member + coordinate/resolve incidents, publish announcements and knowledge (D-05) |
| Admin | app role | Team Lead + membership, codes, roles, shifts, settings, audit read |
| Superadmin | `platform_owners` | Everything, including granting Admin, diagnostics, recovery |

Organizational title and operational roles never feed any authorization check. Full matrix: [PROJECT_SPEC](PROJECT_SPEC.md) §3.

## 4. Threat model

| ID | Threat | Mitigation | Test |
|---|---|---|---|
| T-01 | Anonymous reads data | No `anon` grants; RLS deny by default | SEC-01 |
| T-02 | Pending user reads team data | Every policy requires approved membership | SEC-02 |
| T-03 | Self-approval or role escalation | No client write grants on status/role tables; functions verify caller permission | SEC-03, SEC-04 |
| T-04 | Join-code brute force | High entropy, hashed, expiry, max uses, per-user and global rate limit, authenticated redemption, Supabase Auth limits, optional CAPTCHA | SEC-05 |
| T-05 | Join-code leak | Approval gate, rotate/revoke, raw code never stored or logged | SEC-06 |
| T-06 | Superadmin takeover via signup/profile/client | No client path; `platform_owners` has no client write | SEC-07 |
| T-07 | Owner lockout | Out-of-band recovery runbook (§7); last-Superadmin trigger | SEC-08, SEC-09 |
| T-08 | Service-role or VAPID key exposure | Secrets only in server secret stores; bundle and Git scanning | SEC-10 |
| T-09 | Cross-team access (future-proofing) | `team_id` on every row; every policy scopes by team | SEC-11 |
| T-10 | Suspended member keeps access | Membership checked per query; test with a live JWT | SEC-12 |
| T-11 | `SECURITY DEFINER` abuse | Fixed `search_path`, internal checks, `EXECUTE` revoked from `PUBLIC`/`anon` | SEC-13 |
| T-12 | XSS in notes/announcements | Plain text or sanitized markdown; no raw HTML; strict CSP | SEC-14 |
| T-13 | Push leaks confidential detail | Generic payload only; locked subscription table | SEC-15 |
| T-14 | Audit tampering | Append-only; no update/delete grants; written inside privileged functions | SEC-16 |
| T-15 | Stale/cross-user cached data on shared device | Service worker caches shell only; clear caches on sign-out | SEC-17 |
| T-16 | Lost updates / silent overwrite | Conditional updates in functions; clear conflict result | SEC-18 |
| T-17 | Spam via creation/notification actions | Rate limits on incidents, announcements, requests | SEC-19 |
| T-18 | Supply-chain compromise | Lockfile, `npm audit`, minimal dependencies, justification for each addition | SEC-20 |
| T-19 | Realtime data leakage | Rely on RLS for change events; verify; refetch rather than trust payloads | SEC-21 |

## 5. RLS strategy

- Enable RLS on every table in `public`; add a CI/test check that fails if a table lacks RLS.
- Deny by default; separate policies per command (`SELECT`, `INSERT`, `UPDATE`, `DELETE`) with both `USING` and `WITH CHECK`.
- Helper functions (e.g. `is_approved_member(team_id)`, `has_app_permission(team_id, key)`, `is_superadmin()`) are `SECURITY DEFINER` with fixed `search_path`, stable, minimal, and designed to avoid policy recursion on membership tables.
- Protected columns (`membership_status`, `approved_by`, `resolved_*`, role links) are not client-writable; changes only via privileged functions or column-level privileges plus triggers.
- Views that expose derived data (effective availability) use invoker security so RLS still applies.
- Policies are reviewed alongside migrations; each policy has at least one allow test and one deny test.

## 6. Invitation / joining-code security

- Admin creates a code; the raw value is shown **once**, only a hash is stored (D-02).
- At least 64 bits of entropy; expiry; `max_uses`; `use_count`; revocation; rotation from Admin Settings.
- **Flow (D-03):** the user first creates an account and confirms their email; only a signed-in, email-confirmed session may call the redemption function. Anonymous or unconfirmed callers are rejected.
- Redemption is an authenticated function: constant-style comparison by hash lookup, uniform error messages, attempt recorded in `rate_limit_events`, lockout after repeated failures.
- Redemption only creates a **pending** membership. Access requires explicit approval; roles are granted separately.
- Codes never appear in logs, URLs, analytics or error messages.

### Implemented in Phase 1d (sandbox-verified only)

- Flow: sign up, confirm email, sign in, `redeem_join_code`, **pending**, Admin `review_join_request`. A code never grants access; only an approved membership row does, and only an Admin with MFA can create one.
- Every state change is a SECURITY DEFINER function with a pinned empty `search_path`, an explicit permission check against the target row's own team (cross-team requests are refused), a self-action block, and an audit entry. Unknown rows and missing permission return the same error so existence is not revealed. EXECUTE is limited to `authenticated`; `anon`, `service_role` and PUBLIC cannot call anything.
- Clients have no write access to any membership, role, code, rate-limit or audit table (verified by privilege inventory and by attempted writes).
- Raw codes appear nowhere in tables or audit metadata (verified).
- Suspension takes effect on the next query (verified: a suspended user's team read returns nothing immediately).

## 7. Superadmin bootstrap and recovery (implemented in Phase 1e; sandbox-verified only; D-01 awaiting your confirmation)

**Principle:** Superadmin is never self-service and never evaluated in the frontend.

- **Storage:** `public.platform_owners`. RLS on, no policy, every API privilege revoked, no API-reachable function writes it (checked by privilege inventory, attempted writes and a source-level scan in `verify.sql`).
- **Bootstrap:** `private.bootstrap_superadmin(user_id, team_id, display_name, recovery := false)`. Only the database owner can execute it (every API role is refused; checked). The account must already exist with a confirmed email. It refuses to run when an active Superadmin exists unless `recovery` is true. It creates an **approved** membership with the Member bundle only and writes an audit record with no acting user. Full procedure: [docs/RUNBOOK_SUPERADMIN.md](docs/RUNBOOK_SUPERADMIN.md).
- **Last-owner guard (AC-S10):** a trigger refuses to revoke or delete the last active owner and refuses to change `user_id`. A deliberate override (`uam.allow_last_owner_removal = 'yes'` in the same transaction) exists for decommissioning. It is a safety net against mistakes, not against the database owner.
- **Recovery without the UI (AC-S9):** re-run the function with `recovery := true` from the SQL editor. Tested on plain PostgreSQL only; not on Supabase.
- **Powers:** a Superadmin passes every permission check, may grant and revoke Admin and suspend an Admin, and still needs MFA for every action. Nobody, including another Superadmin, can suspend a Superadmin through the application. A Superadmin cannot grant themselves anything or suspend themselves.
- **Root of trust:** the Supabase project owner account. Protect it with MFA.

## 8. Secrets management

| Secret | Allowed location | Never |
|---|---|---|
| Supabase service-role key | Edge Function secrets / local server env if ever needed | Frontend, Git, `VITE_` vars, prompts, logs |
| VAPID private key | Edge Function secrets | Frontend, Git |
| Database password, JWT secret | Supabase dashboard only | Git, chat |
| Supabase URL, anon/publishable key, VAPID public key | `.env` locally, hosting env vars | (public by design; still not hard-coded) |
| Test account credentials | Git-ignored local env file | Git |

Controls: `.env*` ignored (except `.env.example`); pre-commit/CI secret scanning; production bundle inspected for secret patterns (AC-S3); if a secret leaks, rotate immediately.

## 9. Audit logging

Logged in the same transaction as the action: join-code create/revoke/rotate/redeem outcome, join request review, membership status changes, app-role grants/revocations, Superadmin bootstrap/recovery, operational role create/rename/deactivate, incident ownership change/resolve/reopen, settings changes. Fields: actor, action, entity, entity ID, metadata (no secrets, no raw codes), timestamp. Append-only; readable by Admin/Superadmin only.

## 10. Sessions and revocation

- Authorization is evaluated per query, so suspension blocks reads/writes at once even while a JWT is valid.
- Use short access-token lifetime and refresh tokens per Supabase defaults; review settings in Phase 1.
- On suspension/removal: set status, revoke refresh sessions (via a trusted server path), close Realtime subscription client-side, and verify with a live-JWT test (SEC-12, SEC-21).
- **MFA (D-13, decided):** sensitive Admin/Superadmin actions require a TOTP-verified session (aal2), enforced inside the privileged functions, not only in the UI. Proposed sensitive actions: approve/reject/suspend/reinstate members, grant/revoke app roles, create/revoke/rotate joining codes, change team settings, view audit log, Superadmin diagnostics. Verify Supabase MFA behaviour in Phase 1c/1e.

### Phase 1c auth notes

- Recommended hosted settings: confirm email on, minimum password 12 with lower/upper/digits, secure password change, redirect allow-list limited to known origins. Local `supabase/config.toml` carries these values; the hosted project is changed only with owner approval (README).
- Client validation is usability only; Supabase and the database enforce the rules. The sign-in form applies no password policy.
- No code path reads or logs tokens, passwords or recovery links; `no-console` is an error in lint.
- The browser key is validated at start-up: a service-role JWT or `sb_secret_` key is refused, so a privileged key cannot be shipped by mistake (SEC-10 still scans the bundle).
- Profile writes send only `display_name` and `organizational_title`; the database column grants reject anything else.

## 11. Application hardening

- React escapes by default; no `dangerouslySetInnerHTML` without a sanitizer; markdown rendering restricted.
- Content-Security-Policy and standard security headers at the host (Phase 5).
- Input limits (lengths, counts) in Zod **and** database constraints.
- Generic error messages for auth and code failures; no stack traces to users.
- Dependencies: justified individually; lockfile committed; `npm audit` in CI.

## 12. Residual risks and items to validate before production

| ID | Risk / open item |
|---|---|
| R-01 | Access-token validity after suspension relies on per-query membership checks; verify every policy path and Realtime. |
| R-02 | Realtime RLS behaviour and performance with policies must be tested, not assumed. |
| R-03 | Dependence on Supabase availability, limits and pricing; approval of hosting for team data (D-11). |
| R-04 | Single technical owner is a continuity risk; document recovery and consider a second trusted holder. |
| R-05 | Account-first signup (D-03) permits spam accounts; mitigated by email confirmation and Auth rate limits; CAPTCHA/domain allowlist unresolved (D-18). |
| R-06 | Web Push support varies (notably iOS requires installation); delivery is best-effort. |
| R-07 | Push subscription key storage approach (plain locked table vs encrypted/Vault) undecided. |
| R-08 | Free-tier quotas, backups and point-in-time recovery depend on plan; verify before launch. |
| R-09 | Retention/legal requirements for incident and audit data unknown (D-10). |
| R-10 | Shared-device usage may leave local drafts; sign-out clearing must be tested. |
| R-11 | Phase 1c stores the Supabase session (access and refresh tokens) in browser `localStorage` (supabase-js default), readable by any script that runs on the page. Mitigations: no raw HTML rendering, no third-party scripts, strict CSP (Phase 5), lint ban on `console`. Cookie-based storage would need a server component. Accepted for now; revisit before production. |
| R-12 | Default email templates use PKCE, so a confirmation/reset link only works in the browser that started the flow; the token-hash template change (D-19) fixes this but is a hosted setting and also puts a one-time token in the URL (cleaned client-side, but it passes through the email client and browser history before that). |
| R-13 | A recovery link signs the user in. The app confines that session to the reset form, but the underlying Supabase session exists until the password is set or the user cancels. |
| R-14 | The built-in Supabase email sender is rate-limited and for development; password-reset flooding and deliverability need a real SMTP provider and CAPTCHA decision (D-18, D-20). |
| R-16 | The first Superadmin exists only after the owner runs the bootstrap in the SQL editor on a real project. Until that is done and verified on Supabase, no one can approve requests. The Supabase CLI path for running it (`db query --linked`) is unexercised. |
| R-17 | MFA enforcement reads the JWT `aal` claim. It is verified only against a simulated claim. Real Supabase JWT contents, TOTP enrolment, and the upgrade to aal2 after verification are exercised only by mocked frontend tests. Losing the authenticator device has no verified recovery path (runbook lists the open question). |
| R-18 | `redeem_join_code` reads `auth.users.email_confirmed_at` as the function owner. Whether the hosted `postgres` role may do so is unverified. |
| R-19 | The global cap (50 failed redemptions per 15 minutes across all users) is a **denial-of-service lever**: any signed-in user can burn it and block everyone from joining for 15 minutes. Accepted trade-off against distributed guessing at 80 bits; CAPTCHA or per-IP limits (D-18) would help. |
| R-20 | `rate_limit_events` and `audit_logs` grow without pruning; retention is undecided (D-10). |
| R-22 | Reviewer read policies let an Admin read the name and title of every member of their team and the metadata of their team's joining codes without MFA. Intended, but it widens what a stolen Admin session without MFA can read. |
| R-23 | The guard trigger and the bootstrap function are controls against mistakes and API callers, not against whoever owns the database. |
| R-21 | The `private` schema must never be added to the project's exposed API schemas. `authenticated` holds USAGE on it for the RLS helper; this is unverified on the hosted project (Settings, API). |
| R-15 | All Phase 1c auth behaviour is verified with mocked clients only. Real Auth behaviour (error codes, event order, PKCE, rate limits) is unverified until the manual checklist in [TEST_PLAN](TEST_PLAN.md) §10 runs. |

## 13. Pre-production checklist

- [ ] All tables have RLS; SEC tests pass for every persona.
- [ ] No server secrets in repository history or bundle.
- [ ] Bootstrap and recovery runbooks exercised on dev.
- [ ] MFA enabled on Supabase owner account and privileged app users.
- [ ] Backups and restore procedure verified.
- [ ] Hosting security headers and CSP configured.
- [ ] Open decisions D-04, D-09, D-10, D-11, D-16 closed.
