-- Phase 1d: joining codes, membership, approval, application roles (fixed bundles).
--
-- Model: sign up -> confirm email -> sign in -> redeem_join_code (authenticated, email
-- confirmed) -> PENDING membership -> an authorized Admin approves or rejects. Nothing a
-- client sends can create approval or privilege: all state changes happen in the
-- SECURITY DEFINER functions below, each with an explicit authorization check, a pinned
-- search_path, EXECUTE limited to `authenticated`, and an audit entry.
--
-- Superadmin does not exist yet (Phase 1e). Until then granting or revoking Admin, and
-- suspending an Admin, are refused for everyone; an Admin cannot be created by this
-- migration. Sensitive actions require a TOTP-verified session (aal2, decision D-13).

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.team_memberships (
  id                 uuid primary key default gen_random_uuid(),
  team_id            uuid not null references public.teams (id) on delete restrict,
  user_id            uuid not null references auth.users (id) on delete cascade,
  membership_status  text not null default 'pending',
  approved_by        uuid references auth.users (id) on delete set null,
  approved_at        timestamptz,
  suspended_at       timestamptz,
  created_at         timestamptz not null default pg_catalog.now(),
  updated_at         timestamptz not null default pg_catalog.now(),
  constraint team_memberships_status_valid
    check (membership_status in ('pending', 'approved', 'rejected', 'suspended', 'removed')),
  constraint team_memberships_approved_has_time
    check (membership_status <> 'approved' or approved_at is not null),
  constraint team_memberships_team_user_key unique (team_id, user_id)
);
create index team_memberships_team_status_idx on public.team_memberships (team_id, membership_status);
create trigger team_memberships_set_updated_at
  before update on public.team_memberships
  for each row execute function private.set_updated_at();

create table public.app_roles (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams (id) on delete restrict,
  key          text not null,
  name         text not null,
  permissions  jsonb not null default '[]'::jsonb,
  created_at   timestamptz not null default pg_catalog.now(),
  constraint app_roles_key_valid check (key in ('member', 'team_lead', 'admin')),
  constraint app_roles_permissions_array check (pg_catalog.jsonb_typeof(permissions) = 'array'),
  constraint app_roles_team_key_key unique (team_id, key)
);

create table public.member_app_roles (
  membership_id  uuid not null references public.team_memberships (id) on delete cascade,
  app_role_id    uuid not null references public.app_roles (id) on delete restrict,
  granted_by     uuid references auth.users (id) on delete set null,
  created_at     timestamptz not null default pg_catalog.now(),
  primary key (membership_id, app_role_id)
);

create table public.join_codes (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references public.teams (id) on delete restrict,
  code_hash   text not null,
  label       text,
  expires_at  timestamptz not null,
  max_uses    integer not null,
  use_count   integer not null default 0,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default pg_catalog.now(),
  revoked_at  timestamptz,
  revoked_by  uuid references auth.users (id) on delete set null,
  constraint join_codes_hash_key unique (code_hash),
  constraint join_codes_max_uses_valid check (max_uses between 1 and 50),
  constraint join_codes_use_count_valid check (use_count >= 0 and use_count <= max_uses),
  constraint join_codes_label_valid check (label is null or char_length(label) <= 100),
  constraint join_codes_expiry_after_creation check (expires_at > created_at)
);
create index join_codes_team_idx on public.join_codes (team_id);

create table public.join_requests (
  id            uuid primary key default gen_random_uuid(),
  team_id       uuid not null references public.teams (id) on delete restrict,
  user_id       uuid not null references auth.users (id) on delete cascade,
  join_code_id  uuid references public.join_codes (id) on delete set null,
  status        text not null default 'pending',
  requested_at  timestamptz not null default pg_catalog.now(),
  reviewed_by   uuid references auth.users (id) on delete set null,
  reviewed_at   timestamptz,
  constraint join_requests_status_valid check (status in ('pending', 'approved', 'rejected'))
);
create unique index join_requests_one_pending_key
  on public.join_requests (team_id, user_id) where status = 'pending';
create index join_requests_team_status_idx on public.join_requests (team_id, status);

create table public.rate_limit_events (
  id          bigint generated always as identity primary key,
  user_id     uuid,
  action      text not null,
  created_at  timestamptz not null default pg_catalog.now()
);
create index rate_limit_events_user_action_idx on public.rate_limit_events (user_id, action, created_at desc);
create index rate_limit_events_action_idx on public.rate_limit_events (action, created_at desc);

-- ---------------------------------------------------------------------------
-- Fixed application-role bundles (no permission editor). Permission keys are an allowlist.
-- ---------------------------------------------------------------------------
create or replace function private.validate_app_role_permissions()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if exists (
    select 1 from pg_catalog.jsonb_array_elements_text(new.permissions) as p(perm)
    where p.perm not in ('members.review', 'members.suspend', 'join_codes.manage', 'app_roles.grant_basic')
  ) then
    raise exception 'unknown permission key' using errcode = '23514';
  end if;
  return new;
end;
$$;
create trigger app_roles_validate_permissions
  before insert or update on public.app_roles
  for each row execute function private.validate_app_role_permissions();

-- Every team gets the three bundles. Member and Team Lead hold no database permission keys
-- yet (their capabilities arrive with the features in Phases 2-4); Admin holds the
-- membership-administration keys. Granting Admin is Superadmin-only (Phase 1e).
create or replace function private.seed_app_roles(p_team_id uuid)
returns void language sql security invoker set search_path = ''
as $$
  insert into public.app_roles (team_id, key, name, permissions) values
    (p_team_id, 'member',    'Member',    '[]'::jsonb),
    (p_team_id, 'team_lead', 'Team Lead', '[]'::jsonb),
    (p_team_id, 'admin',     'Admin',     '["members.review","members.suspend","join_codes.manage","app_roles.grant_basic"]'::jsonb)
  on conflict (team_id, key) do nothing;
$$;

create or replace function private.seed_app_roles_trigger()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.seed_app_roles(new.id);
  return new;
end;
$$;
create trigger teams_seed_app_roles
  after insert on public.teams
  for each row execute function private.seed_app_roles_trigger();

select private.seed_app_roles(t.id) from public.teams t;

-- ---------------------------------------------------------------------------
-- Authorization helpers. SECURITY DEFINER so they can read the membership tables without
-- recursing through RLS; fixed empty search_path; they only ever answer about auth.uid().
-- ---------------------------------------------------------------------------
create or replace function private.is_approved_member(p_team_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.team_memberships m
    where m.team_id = p_team_id
      and m.user_id = (select auth.uid())
      and m.membership_status = 'approved'
  );
$$;

create or replace function private.has_permission(p_team_id uuid, p_permission text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
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

-- Sensitive actions need a TOTP-verified session (D-13). Reads the JWT only.
create or replace function private.require_aal2()
returns void language plpgsql stable security invoker set search_path = ''
as $$
begin
  if (auth.jwt() ->> 'aal') is distinct from 'aal2' then
    raise exception 'multi-factor authentication required' using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Client-callable functions (schema public so supabase.rpc can reach them).
-- ---------------------------------------------------------------------------

-- Redeem a joining code. Expected failures RETURN a status (never raise) so that the failed
-- attempt that was recorded for rate limiting is committed. Unknown, expired, revoked and
-- exhausted codes are indistinguishable (invalid_code).
create or replace function public.redeem_join_code(p_code text, p_display_name text, p_title text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid      uuid := auth.uid();
  v_name     text := btrim(coalesce(p_display_name, ''));
  v_title    text := nullif(btrim(coalesce(p_title, '')), '');
  v_norm     text;
  v_hash     text;
  v_code     public.join_codes%rowtype;
  v_member   public.team_memberships%rowtype;
  v_member_id uuid;
  v_request_id uuid;
  v_fail_user integer;
  v_fail_all  integer;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users u where u.id = v_uid and u.email_confirmed_at is not null) then
    raise exception 'email address not confirmed' using errcode = '42501';
  end if;
  if v_name = '' or char_length(v_name) > 80 or (v_title is not null and char_length(v_title) > 100) then
    raise exception 'invalid profile values' using errcode = '22023';
  end if;

  -- Rate limit: failures only, per user and across all users.
  select count(*) into v_fail_user from public.rate_limit_events e
    where e.action = 'join_code_failed' and e.user_id = v_uid and e.created_at > pg_catalog.now() - interval '15 minutes';
  select count(*) into v_fail_all from public.rate_limit_events e
    where e.action = 'join_code_failed' and e.created_at > pg_catalog.now() - interval '15 minutes';
  if v_fail_user >= 5 or v_fail_all >= 50 then
    return pg_catalog.jsonb_build_object('status', 'rate_limited');
  end if;

  v_norm := pg_catalog.upper(pg_catalog.regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_hash := pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_norm, 'UTF8')), 'hex');

  select * into v_code from public.join_codes c
    where c.code_hash = v_hash and c.revoked_at is null
      and c.expires_at > pg_catalog.now() and c.use_count < c.max_uses;
  if not found or char_length(v_norm) < 10 then
    insert into public.rate_limit_events (user_id, action) values (v_uid, 'join_code_failed');
    return pg_catalog.jsonb_build_object('status', 'invalid_code');
  end if;

  select * into v_member from public.team_memberships m
    where m.team_id = v_code.team_id and m.user_id = v_uid for update;
  if found then
    if v_member.membership_status = 'approved' then
      return pg_catalog.jsonb_build_object('status', 'already_member');
    elsif v_member.membership_status = 'pending' then
      return pg_catalog.jsonb_build_object('status', 'already_pending');
    elsif v_member.membership_status <> 'rejected' then
      return pg_catalog.jsonb_build_object('status', 'blocked');
    end if;
  end if;

  -- Consume one use atomically (guards against concurrent redemption of the last use).
  update public.join_codes c set use_count = c.use_count + 1
    where c.id = v_code.id and c.revoked_at is null
      and c.expires_at > pg_catalog.now() and c.use_count < c.max_uses;
  if not found then
    insert into public.rate_limit_events (user_id, action) values (v_uid, 'join_code_failed');
    return pg_catalog.jsonb_build_object('status', 'invalid_code');
  end if;

  insert into public.profiles (user_id, display_name, organizational_title)
    values (v_uid, v_name, v_title)
    on conflict (user_id) do update
      set display_name = excluded.display_name, organizational_title = excluded.organizational_title;

  if v_member.id is null then
    insert into public.team_memberships (team_id, user_id, membership_status)
      values (v_code.team_id, v_uid, 'pending') returning id into v_member_id;
  else
    update public.team_memberships m
      set membership_status = 'pending', approved_by = null, approved_at = null, suspended_at = null
      where m.id = v_member.id returning m.id into v_member_id;
  end if;

  insert into public.join_requests (team_id, user_id, join_code_id, status)
    values (v_code.team_id, v_uid, v_code.id, 'pending') returning id into v_request_id;

  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_code.team_id, v_uid, 'join_code.redeemed', 'join_request', v_request_id,
            pg_catalog.jsonb_build_object('join_code_id', v_code.id, 'membership_id', v_member_id));

  return pg_catalog.jsonb_build_object('status', 'pending');
end;
$$;

-- Create a joining code. The raw code is returned ONCE and never stored.
create or replace function public.create_join_code(
  p_team_id uuid, p_max_uses integer default 1, p_valid_days integer default 7, p_label text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid     uuid := auth.uid();
  v_raw     text;
  v_grouped text;
  v_id      uuid;
  v_expires timestamptz;
begin
  if v_uid is null or not private.has_permission(p_team_id, 'join_codes.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if p_max_uses is null or p_max_uses not between 1 and 50
     or p_valid_days is null or p_valid_days not between 1 and 30
     or (p_label is not null and char_length(p_label) > 100) then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;

  -- 80 random bits: first 10 hex characters of two random UUIDs, shown in groups of five.
  v_raw := pg_catalog.upper(
    pg_catalog.substr(pg_catalog.replace(gen_random_uuid()::text, '-', ''), 1, 10) ||
    pg_catalog.substr(pg_catalog.replace(gen_random_uuid()::text, '-', ''), 1, 10));
  v_grouped := pg_catalog.substr(v_raw, 1, 5) || '-' || pg_catalog.substr(v_raw, 6, 5) || '-' ||
               pg_catalog.substr(v_raw, 11, 5) || '-' || pg_catalog.substr(v_raw, 16, 5);
  v_expires := pg_catalog.now() + pg_catalog.make_interval(days => p_valid_days);

  insert into public.join_codes (team_id, code_hash, label, expires_at, max_uses, created_by)
    values (p_team_id, pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(v_raw, 'UTF8')), 'hex'),
            p_label, v_expires, p_max_uses, v_uid)
    returning id into v_id;

  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (p_team_id, v_uid, 'join_code.created', 'join_code', v_id,
            pg_catalog.jsonb_build_object('max_uses', p_max_uses, 'expires_at', v_expires));

  return pg_catalog.jsonb_build_object('id', v_id, 'code', v_grouped, 'expires_at', v_expires);
end;
$$;

create or replace function public.revoke_join_code(p_code_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_code public.join_codes%rowtype;
begin
  select * into v_code from public.join_codes c where c.id = p_code_id;
  -- Unknown code and missing permission are indistinguishable.
  if v_uid is null or not found or not private.has_permission(v_code.team_id, 'join_codes.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  update public.join_codes c set revoked_at = pg_catalog.now(), revoked_by = v_uid
    where c.id = p_code_id and c.revoked_at is null;
  if found then
    insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id)
      values (v_code.team_id, v_uid, 'join_code.revoked', 'join_code', p_code_id);
  end if;
  return pg_catalog.jsonb_build_object('status', 'revoked');
end;
$$;

create or replace function public.review_join_request(p_request_id uuid, p_decision text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_req public.join_requests%rowtype;
begin
  select * into v_req from public.join_requests r where r.id = p_request_id for update;
  if v_uid is null or not found or not private.has_permission(v_req.team_id, 'members.review') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_req.user_id = v_uid then
    raise exception 'you cannot review your own request' using errcode = '42501';
  end if;
  if p_decision not in ('approve', 'reject') then
    raise exception 'invalid decision' using errcode = '22023';
  end if;
  if v_req.status <> 'pending' then
    return pg_catalog.jsonb_build_object('status', 'not_pending');
  end if;

  if p_decision = 'approve' then
    update public.team_memberships m
      set membership_status = 'approved', approved_by = v_uid, approved_at = pg_catalog.now(), suspended_at = null
      where m.team_id = v_req.team_id and m.user_id = v_req.user_id and m.membership_status = 'pending';
    insert into public.member_app_roles (membership_id, app_role_id, granted_by)
      select m.id, a.id, v_uid
      from public.team_memberships m
      join public.app_roles a on a.team_id = m.team_id and a.key = 'member'
      where m.team_id = v_req.team_id and m.user_id = v_req.user_id
      on conflict do nothing;
  else
    update public.team_memberships m set membership_status = 'rejected'
      where m.team_id = v_req.team_id and m.user_id = v_req.user_id and m.membership_status = 'pending';
  end if;

  update public.join_requests r
    set status = case when p_decision = 'approve' then 'approved' else 'rejected' end,
        reviewed_by = v_uid, reviewed_at = pg_catalog.now()
    where r.id = p_request_id;

  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_req.team_id, v_uid,
            case when p_decision = 'approve' then 'membership.approved' else 'membership.rejected' end,
            'join_request', p_request_id, pg_catalog.jsonb_build_object('subject_user_id', v_req.user_id));

  return pg_catalog.jsonb_build_object('status', case when p_decision = 'approve' then 'approved' else 'rejected' end);
end;
$$;

-- Suspend / reinstate. Never self, never an Admin (Admin changes need Superadmin, Phase 1e).
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
  if v_m.user_id = v_uid or exists (
       select 1 from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id
       where r.membership_id = v_m.id and a.key = 'admin') then
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

create or replace function public.reinstate_member(p_membership_id uuid)
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
  if v_m.user_id = v_uid then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  if v_m.membership_status <> 'suspended' then
    return pg_catalog.jsonb_build_object('status', 'not_suspended');
  end if;
  update public.team_memberships m set membership_status = 'approved', suspended_at = null where m.id = v_m.id;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'membership.reinstated', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('subject_user_id', v_m.user_id));
  return pg_catalog.jsonb_build_object('status', 'approved');
end;
$$;

-- Grant / revoke the Team Lead bundle. Admin is Superadmin-only and not available until 1e.
create or replace function public.grant_app_role(p_membership_id uuid, p_role_key text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.team_memberships%rowtype;
  v_role uuid;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'app_roles.grant_basic') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_m.user_id = v_uid or p_role_key is distinct from 'team_lead' then
    -- Includes any attempt to grant Admin (Superadmin-only; Phase 1e) or to self-grant.
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
  if v_m.user_id = v_uid or p_role_key is distinct from 'team_lead' then
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

-- ---------------------------------------------------------------------------
-- RLS, grants, policies
-- ---------------------------------------------------------------------------
alter table public.team_memberships enable row level security;
alter table public.app_roles        enable row level security;
alter table public.member_app_roles enable row level security;
alter table public.join_codes       enable row level security;
alter table public.join_requests    enable row level security;
alter table public.rate_limit_events enable row level security;

revoke all on table public.team_memberships, public.app_roles, public.member_app_roles,
  public.join_codes, public.join_requests, public.rate_limit_events
  from public, anon, authenticated, service_role;

-- Clients may read only specific columns of three tables. Everything else is function-only.
grant select (id, name, timezone) on table public.teams to authenticated;
grant select (id, team_id, user_id, membership_status, approved_at) on table public.team_memberships to authenticated;
grant select (id, team_id, status, requested_at, reviewed_at) on table public.join_requests to authenticated;

create policy teams_select_member on public.teams
  for select to authenticated
  using (private.is_approved_member(id));

create policy team_memberships_select_own on public.team_memberships
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy join_requests_select_own on public.join_requests
  for select to authenticated
  using (user_id = (select auth.uid()));

-- Helper and function privileges. Private helpers are not callable by default.
-- Explicit revoke: ALTER DEFAULT PRIVILEGES ... IN SCHEMA cannot remove the built-in
-- "PUBLIC may execute new functions" default, so every migration that adds a private
-- function must revoke it again (the verify script checks this).
revoke execute on all functions in schema private from public;
grant usage on schema private to authenticated;
grant execute on function private.is_approved_member(uuid) to authenticated;
-- has_permission, require_aal2 and the seed/validation helpers are only ever called from
-- the definer functions below (running as owner) or from triggers, never by API roles.

revoke execute on function
  public.redeem_join_code(text, text, text),
  public.create_join_code(uuid, integer, integer, text),
  public.revoke_join_code(uuid),
  public.review_join_request(uuid, text),
  public.suspend_member(uuid, text),
  public.reinstate_member(uuid),
  public.grant_app_role(uuid, text),
  public.revoke_app_role(uuid, text)
  from public, anon, service_role;
grant execute on function
  public.redeem_join_code(text, text, text),
  public.create_join_code(uuid, integer, integer, text),
  public.revoke_join_code(uuid),
  public.review_join_request(uuid, text),
  public.suspend_member(uuid, text),
  public.reinstate_member(uuid),
  public.grant_app_role(uuid, text),
  public.revoke_app_role(uuid, text)
  to authenticated;

comment on schema private is
  'Internal helpers. Not exposed through the API. authenticated has USAGE only so RLS policies can call private.is_approved_member; every other private function is not executable by API roles.';
