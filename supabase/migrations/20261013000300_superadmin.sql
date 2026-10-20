-- Phase 1e: Superadmin, Admin management, reviewer read access.
--
-- Superadmin is an APPLICATION-level privilege held in public.platform_owners. No API role
-- can read or write that table and no function reachable from the API inserts into it. The
-- first row is created only by private.bootstrap_superadmin(), which no API role may
-- execute: the project owner runs it once from the Supabase SQL editor (a trusted
-- environment). See docs/RUNBOOK_SUPERADMIN.md.
--
-- NOTE on private-schema functions: every function created here is explicitly revoked from
-- PUBLIC. ALTER DEFAULT PRIVILEGES cannot remove the built-in "PUBLIC may execute new
-- functions" default (see the note in 20261013000200_membership.sql).

-- ---------------------------------------------------------------------------
-- platform_owners
-- ---------------------------------------------------------------------------
create table public.platform_owners (
  user_id     uuid primary key references auth.users (id) on delete restrict,
  granted_at  timestamptz not null default pg_catalog.now(),
  granted_by  uuid references auth.users (id) on delete set null,
  revoked_at  timestamptz,
  note        text,
  constraint platform_owners_note_valid check (note is null or char_length(note) <= 200)
);
comment on table public.platform_owners is
  'Superadmins. RLS on, no policy, no API privileges, no API-reachable function writes it. Created only by private.bootstrap_superadmin() run in the SQL editor.';

alter table public.platform_owners enable row level security;
revoke all on table public.platform_owners from public, anon, authenticated, service_role;

-- Guard: the last active Superadmin cannot be revoked or deleted, even by SQL, unless the
-- operator deliberately sets `uam.allow_last_owner_removal = 'yes'` in the same transaction
-- (decommissioning, documented in the runbook). user_id is immutable. This is a safety net
-- against mistakes, not a defence against a malicious database owner (see SECURITY.md).
create or replace function private.guard_last_platform_owner()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if tg_op = 'TRUNCATE' then
    if coalesce(pg_catalog.current_setting('uam.allow_last_owner_removal', true), '') <> 'yes' then
      raise exception 'platform_owners cannot be truncated' using errcode = '42501';
    end if;
    return null;
  end if;
  if tg_op = 'UPDATE' and new.user_id <> old.user_id then
    raise exception 'platform_owners.user_id is immutable' using errcode = '42501';
  end if;
  if old.revoked_at is null
     and (tg_op = 'DELETE' or new.revoked_at is not null)
     and coalesce(pg_catalog.current_setting('uam.allow_last_owner_removal', true), '') <> 'yes'
     and not exists (select 1 from public.platform_owners o where o.revoked_at is null and o.user_id <> old.user_id) then
    raise exception 'cannot remove the last active Superadmin' using errcode = '42501';
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke execute on function private.guard_last_platform_owner() from public;
create trigger platform_owners_guard
  before update or delete on public.platform_owners
  for each row execute function private.guard_last_platform_owner();
create trigger platform_owners_guard_truncate
  before truncate on public.platform_owners
  for each statement execute function private.guard_last_platform_owner();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function private.is_superadmin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.platform_owners o
    where o.user_id = (select auth.uid()) and o.revoked_at is null
  );
$$;
revoke execute on function private.is_superadmin() from public;

-- Superadmin passes every permission check; everyone else needs an APPROVED membership
-- holding a bundle that contains the key (so suspension removes every permission at once).
create or replace function private.has_permission(p_team_id uuid, p_permission text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select private.is_superadmin() or exists (
    select 1
    from public.team_memberships m
    join public.member_app_roles r on r.membership_id = m.id
    join public.app_roles a on a.id = r.app_role_id and a.team_id = m.team_id
    where m.team_id = p_team_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'approved'
      and pg_catalog.jsonb_exists(a.permissions, p_permission)
  );
$$;
-- Called from RLS policies, so authenticated needs EXECUTE. It only ever answers about
-- auth.uid() and the private schema is not exposed through the API.
grant execute on function private.has_permission(uuid, text) to authenticated;

-- May the caller review this user? Scoped by membership even for a Superadmin, so profiles
-- of users with no membership stay private.
create or replace function private.can_review_user(p_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.team_memberships tm
    where tm.user_id = p_user_id and private.has_permission(tm.team_id, 'members.review')
  );
$$;
revoke execute on function private.can_review_user(uuid) from public;
grant execute on function private.can_review_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Functions changed from Phase 1d: Admin is manageable, by Superadmin only.
-- ---------------------------------------------------------------------------
create or replace function public.grant_app_role(p_membership_id uuid, p_role_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_m    public.team_memberships%rowtype;
  v_role uuid;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'app_roles.grant_basic') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_m.user_id = v_uid
     or p_role_key is null or p_role_key not in ('team_lead', 'admin')
     or (p_role_key = 'admin' and not private.is_superadmin()) then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  if v_m.membership_status <> 'approved' then
    return pg_catalog.jsonb_build_object('status', 'not_approved');
  end if;
  select a.id into v_role from public.app_roles a where a.team_id = v_m.team_id and a.key = p_role_key;
  insert into public.member_app_roles (membership_id, app_role_id, granted_by) values (v_m.id, v_role, v_uid)
    on conflict do nothing;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'app_role.granted', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('role', p_role_key, 'subject_user_id', v_m.user_id));
  return pg_catalog.jsonb_build_object('status', 'granted');
end;
$$;

create or replace function public.revoke_app_role(p_membership_id uuid, p_role_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.team_memberships%rowtype;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'app_roles.grant_basic') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_m.user_id = v_uid
     or p_role_key is null or p_role_key not in ('team_lead', 'admin')
     or (p_role_key = 'admin' and not private.is_superadmin()) then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  delete from public.member_app_roles r using public.app_roles a
    where r.membership_id = v_m.id and a.id = r.app_role_id and a.key = p_role_key;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'app_role.revoked', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('role', p_role_key, 'subject_user_id', v_m.user_id));
  return pg_catalog.jsonb_build_object('status', 'revoked');
end;
$$;

-- A Superadmin may suspend an Admin; an Admin may not. Nobody can suspend themselves or a
-- Superadmin through the application.
create or replace function public.suspend_member(p_membership_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.team_memberships%rowtype;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'members.suspend') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_m.user_id = v_uid
     or exists (select 1 from public.platform_owners o where o.user_id = v_m.user_id and o.revoked_at is null)
     or (not private.is_superadmin() and exists (
           select 1 from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id
           where r.membership_id = v_m.id and a.key = 'admin')) then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  if p_reason is not null and char_length(p_reason) > 200 then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  if v_m.membership_status <> 'approved' then
    return pg_catalog.jsonb_build_object('status', 'not_approved');
  end if;
  update public.team_memberships m set membership_status = 'suspended', suspended_at = pg_catalog.now() where m.id = v_m.id;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'membership.suspended', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('subject_user_id', v_m.user_id, 'reason', p_reason));
  return pg_catalog.jsonb_build_object('status', 'suspended');
end;
$$;

-- What may the caller do? Own information only. Used to decide what to SHOW; the database
-- still enforces every action.
create or replace function public.get_my_access(p_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid   uuid := auth.uid();
  v_super boolean;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  v_super := private.is_superadmin();
  return pg_catalog.jsonb_build_object(
    'superadmin', v_super,
    'member', private.is_approved_member(p_team_id),
    'permissions', case when v_super then
        '["app_roles.grant_basic","join_codes.manage","members.review","members.suspend"]'::jsonb
      else (
        select coalesce(pg_catalog.jsonb_agg(distinct p.perm), '[]'::jsonb)
        from public.team_memberships m
        join public.member_app_roles r on r.membership_id = m.id
        join public.app_roles a on a.id = r.app_role_id and a.team_id = m.team_id
        cross join lateral pg_catalog.jsonb_array_elements_text(a.permissions) as p(perm)
        where m.team_id = p_team_id and m.user_id = v_uid and m.membership_status = 'approved')
      end);
end;
$$;
revoke execute on function public.get_my_access(uuid) from public, anon, service_role;
grant execute on function public.get_my_access(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Reviewer read access (so the administrative screen can list requests, members and codes).
-- Reads need no MFA; every ACTION still does. Column grants keep hashes and actor ids out.
-- ---------------------------------------------------------------------------
grant select (suspended_at) on table public.team_memberships to authenticated;
grant select (user_id) on table public.join_requests to authenticated;
grant select (id, team_id, label, expires_at, max_uses, use_count, created_at, revoked_at)
  on table public.join_codes to authenticated;

create policy team_memberships_select_reviewers on public.team_memberships
  for select to authenticated
  using (private.has_permission(team_id, 'members.review'));

create policy join_requests_select_reviewers on public.join_requests
  for select to authenticated
  using (private.has_permission(team_id, 'members.review'));

create policy profiles_select_reviewers on public.profiles
  for select to authenticated
  using (private.can_review_user(user_id));

create policy join_codes_select_managers on public.join_codes
  for select to authenticated
  using (private.has_permission(team_id, 'join_codes.manage'));

-- ---------------------------------------------------------------------------
-- One-time bootstrap / recovery. NOT callable by any API role. Run by the project owner in
-- the Supabase SQL editor:   select private.bootstrap_superadmin('<user uuid>', '<team uuid>', 'Display Name');
-- Refuses when an active Superadmin already exists, unless p_recovery is true (restore access
-- after a lock-out, or add a second Superadmin). The account must already exist and have a
-- confirmed email. Creates an APPROVED membership with the Member bundle only; Admin is never
-- granted here. Audited with no acting user.
-- ---------------------------------------------------------------------------
create or replace function private.bootstrap_superadmin(
  p_user_id uuid, p_team_id uuid, p_display_name text, p_recovery boolean default false)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare
  v_name     text := btrim(coalesce(p_display_name, ''));
  v_has_owner boolean;
  v_mid      uuid;
begin
  if p_user_id is null or p_team_id is null
     or not exists (select 1 from auth.users u where u.id = p_user_id and u.email_confirmed_at is not null)
     or not exists (select 1 from public.teams t where t.id = p_team_id)
     or v_name = '' or char_length(v_name) > 80 then
    raise exception 'invalid bootstrap arguments (user must exist with a confirmed email, team must exist, name 1-80 characters)'
      using errcode = '22023';
  end if;

  select exists (select 1 from public.platform_owners o where o.revoked_at is null) into v_has_owner;
  if v_has_owner and not coalesce(p_recovery, false) then
    raise exception 'a Superadmin already exists; run again with p_recovery => true only for recovery'
      using errcode = '42501';
  end if;

  insert into public.platform_owners (user_id, note)
    values (p_user_id, case when v_has_owner then 'recovery' else 'bootstrap' end)
    on conflict (user_id) do update set revoked_at = null;

  insert into public.profiles (user_id, display_name) values (p_user_id, v_name)
    on conflict (user_id) do update set display_name = excluded.display_name;

  insert into public.team_memberships (team_id, user_id, membership_status, approved_at)
    values (p_team_id, p_user_id, 'approved', pg_catalog.now())
    on conflict (team_id, user_id) do update
      set membership_status = 'approved', suspended_at = null,
          approved_at = coalesce(public.team_memberships.approved_at, pg_catalog.now())
    returning id into v_mid;

  insert into public.member_app_roles (membership_id, app_role_id)
    select v_mid, a.id from public.app_roles a where a.team_id = p_team_id and a.key = 'member'
    on conflict do nothing;

  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (p_team_id, null,
            case when v_has_owner then 'superadmin.recovered' else 'superadmin.bootstrapped' end,
            'platform_owner', p_user_id, pg_catalog.jsonb_build_object('subject_user_id', p_user_id));

  return pg_catalog.jsonb_build_object('status', case when v_has_owner then 'recovered' else 'bootstrapped' end);
end;
$$;
revoke execute on function private.bootstrap_superadmin(uuid, uuid, text, boolean)
  from public, anon, authenticated, service_role;
