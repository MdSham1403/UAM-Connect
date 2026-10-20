# Runbook: Superadmin bootstrap and recovery

Status: **written and exercised only on a plain PostgreSQL 16 stand-in** (through `supabase db query --db-url`). Not yet run on a Supabase project. Every step below that touches Supabase itself is unverified until you run it.

Design (D-01, still awaiting your confirmation): Superadmin is a row in `public.platform_owners`. No API role can read or write that table, and no function reachable from the API can create a Superadmin. The only way to create one is `private.bootstrap_superadmin(...)`, which **only the database owner can execute**. You run it from the Supabase SQL editor (or the CLI) with your owner credentials. Nothing about it is stored in the app, in Git, or in the browser.

## Rules

- Never hard-code an email address, user id or "owner" flag anywhere in the app or the repository.
- Never paste the project's database password, service-role key, access tokens or recovery codes into chat, Git or an issue.
- Use **synthetic data only** until the owner approves Supabase for real team data (D-11).
- Keep the Supabase account that owns the project protected with MFA. It is the root of trust: whoever controls it can run this function, disable the safety trigger, or edit any row.

## 1. First-time bootstrap

Prerequisites: the four migrations are applied (`npx supabase db push`), at least one team row exists (the synthetic seed team, see README step 7), and **you have already signed up in the app with your own email and confirmed it**. The function refuses an account that does not exist or has no confirmed email.

1. In the Supabase dashboard open **SQL Editor** (you are acting as the `postgres` owner role). Look up the two ids you need:

```sql
select u.id as user_id, u.email, u.email_confirmed_at is not null as confirmed
from auth.users u where u.email = 'YOUR-OWNER-EMAIL';

select id as team_id, name from public.teams;
```

2. Run the bootstrap with those ids. Replace the placeholders **in the editor only**; do not save the filled-in statement anywhere that syncs to Git:

```sql
select private.bootstrap_superadmin('<USER_ID>', '<TEAM_ID>', 'Your Display Name');
```

Expected result: `{"status": "bootstrapped"}`. The function:
- inserts you into `platform_owners`;
- creates your profile and an **approved** membership with the Member bundle only (it never grants the Admin role: Superadmin does not need it);
- writes an audit record `superadmin.bootstrapped` with no acting user.

3. Confirm:

```sql
select user_id, revoked_at from public.platform_owners;
select action, actor_user_id, created_at from public.audit_logs order by created_at desc limit 5;
```

4. A second run is refused ("a Superadmin already exists") unless you pass `true` as the fourth argument. That is intended: it makes the function safe to leave in the database.

## 2. First sign-in as Superadmin

1. Sign in to the app. The Administration section appears because the server reports Superadmin access.
2. Superadmin actions need an authenticator code. The screen offers MFA setup: scan the QR code with an authenticator app, enter the code, and keep the secret key somewhere safe and offline.
3. Create a joining code, share it privately, and approve a test member to complete the loop.

## 3. Add a second Superadmin (recommended break-glass account)

Create and confirm a second account for yourself (a different mailbox that you control), enrol MFA on it, then in the SQL editor:

```sql
select private.bootstrap_superadmin('<SECOND_USER_ID>', '<TEAM_ID>', 'Break-glass Account', true);
```

Expected: `{"status": "recovered"}` (the word "recovered" is used for any run that adds or restores an owner after the first). Store its credentials and MFA secret offline.

## 4. Recovery scenarios

| Situation | Action |
|---|---|
| Forgot password | Use the app's "Forgot password?" flow. |
| Lost authenticator device or secret | Not solved by this function. Remove the user's MFA factor in the Supabase dashboard (Authentication, Users) if your dashboard offers it, then enrol again. **Unverified.** If it is not offered, ask me for a safe SQL alternative; do not edit `auth` tables blindly. |
| Superadmin was revoked or the account is locked out | `select private.bootstrap_superadmin('<USER_ID>', '<TEAM_ID>', 'Name', true);` restores the owner row (clears `revoked_at`), re-approves the membership and audits `superadmin.recovered`. |
| Your Superadmin account is suspended as a member | Same command: it sets the membership back to approved. Superadmins cannot be suspended through the app. |
| You want to remove the very last Superadmin (decommission) | The guard trigger refuses this on purpose. In one SQL-editor run: `set local uam.allow_last_owner_removal = 'yes';` then the `update public.platform_owners set revoked_at = now() where user_id = '<USER_ID>';` (statements in the same transaction, e.g. wrapped in `begin; ... commit;`). |

## 5. Verifying the safeguards after any change

```bat
npm run db:verify
```

Expect `VERIFY RESULT: PASS`. It checks that no API role can read or write `platform_owners`, that nothing but the owner can run the bootstrap function, that the last Superadmin cannot be removed by accident, and that suspension and revocation remove powers immediately.

## What these safeguards do **not** do

- The guard trigger protects against mistakes, not against the database owner, who can drop it. The Supabase project owner account is therefore the root of trust.
- Recovery depends on that account. If it is lost, only Supabase account recovery can help.
- The `supabase db query --linked` path uses Supabase's management API and has not been exercised here; the SQL editor is the primary path.
