-- Phase 2a: configurable operational roles and the team directory.
--
-- Operational roles (BAU / Ticketing, Queue Manager, ...) describe WHAT a person covers. They
-- are separate from organizational title and from application permissions: nothing here is
-- ever read by an authorization check except the single permission key that guards who may
-- manage them (`operational_roles.manage`, part of the Admin bundle).
--
-- Tables have RLS enabled, no client policy and no API privileges. Clients read through two
-- functions and change data only through four audited functions that require an approved
-- Admin (or Superadmin) with a TOTP-verified session. Roles are never deleted (foreign keys
-- restrict it); they are deactivated, which keeps history.

-- ---------------------------------------------------------------------------
-- Permission key for the Admin bundle
-- ---------------------------------------------------------------------------
create or replace function private.validate_app_role_permissions()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  if exists (
    select 1 from pg_catalog.jsonb_array_elements_text(new.permissions) as p(perm)
    where p.perm not in ('members.review', 'members.suspend', 'join_codes.manage',
                         'app_roles.grant_basic', 'operational_roles.manage')
  ) then
    raise exception 'unknown permission key' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function private.seed_app_roles(p_team_id uuid)
returns void language sql security invoker set search_path = ''
as $$
  insert into public.app_roles (team_id, key, name, permissions) values
    (p_team_id, 'member',    'Member',    '[]'::jsonb),
    (p_team_id, 'team_lead', 'Team Lead', '[]'::jsonb),
    (p_team_id, 'admin',     'Admin',     '["members.review","members.suspend","join_codes.manage","app_roles.grant_basic","operational_roles.manage"]'::jsonb)
  on conflict (team_id, key) do nothing;
$$;

update public.app_roles
  set permissions = permissions || '["operational_roles.manage"]'::jsonb
  where key = 'admin' and not pg_catalog.jsonb_exists(permissions, 'operational_roles.manage');

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------
create table public.operational_roles (
  id           uuid primary key default gen_random_uuid(),
  team_id      uuid not null references public.teams (id) on delete restrict,
  name         text not null,
  description  text,
  is_active    boolean not null default true,
  created_by   uuid references auth.users (id) on delete set null,
  created_at   timestamptz not null default pg_catalog.now(),
  updated_at   timestamptz not null default pg_catalog.now(),
  constraint operational_roles_name_valid check (btrim(name) <> '' and char_length(name) <= 60),
  constraint operational_roles_description_valid check (description is null or char_length(description) <= 200)
);
create unique index operational_roles_team_name_key on public.operational_roles (team_id, lower(name));
create trigger operational_roles_set_updated_at
  before update on public.operational_roles
  for each row execute function private.set_updated_at();

create table public.member_operational_roles (
  membership_id        uuid not null references public.team_memberships (id) on delete cascade,
  operational_role_id  uuid not null references public.operational_roles (id) on delete restrict,
  is_primary           boolean not null default false,
  assigned_by          uuid references auth.users (id) on delete set null,
  created_at           timestamptz not null default pg_catalog.now(),
  primary key (membership_id, operational_role_id)
);
-- A member may hold several roles but at most one primary.
create unique index member_operational_roles_one_primary_key
  on public.member_operational_roles (membership_id) where is_primary;
create index member_operational_roles_role_idx on public.member_operational_roles (operational_role_id);

alter table public.operational_roles enable row level security;
alter table public.member_operational_roles enable row level security;
revoke all on table public.operational_roles, public.member_operational_roles
  from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- The six initial roles, for every team (existing and future). Admins may rename,
-- deactivate or add to them without any code change.
-- ---------------------------------------------------------------------------
create or replace function private.seed_operational_roles(p_team_id uuid)
returns void language sql security invoker set search_path = ''
as $$
  insert into public.operational_roles (team_id, name) values
    (p_team_id, 'BAU / Ticketing'), (p_team_id, 'Queue Manager'), (p_team_id, 'Onboarding'),
    (p_team_id, 'Resignation'), (p_team_id, 'Retain'), (p_team_id, 'Reconciliation')
  on conflict do nothing;
$$;
create or replace function private.seed_operational_roles_trigger()
returns trigger language plpgsql security invoker set search_path = ''
as $$
begin
  perform private.seed_operational_roles(new.id);
  return new;
end;
$$;
revoke execute on function private.seed_operational_roles(uuid) from public;
revoke execute on function private.seed_operational_roles_trigger() from public;
create trigger teams_seed_operational_roles
  after insert on public.teams
  for each row execute function private.seed_operational_roles_trigger();
select private.seed_operational_roles(t.id) from public.teams t;

-- ---------------------------------------------------------------------------
-- Changed from Phase 1e: the Superadmin's reported permission list gains the new key.
-- ---------------------------------------------------------------------------
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
        '["app_roles.grant_basic","join_codes.manage","members.review","members.suspend","operational_roles.manage"]'::jsonb
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

-- ---------------------------------------------------------------------------
-- Writes: Admin or Superadmin, TOTP-verified session, audited. Unknown ids and missing
-- permission are indistinguishable (42501).
-- ---------------------------------------------------------------------------
create or replace function public.create_operational_role(p_team_id uuid, p_name text, p_description text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_desc text := nullif(btrim(coalesce(p_description, '')), '');
  v_id   uuid;
begin
  if v_uid is null or not private.has_permission(p_team_id, 'operational_roles.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  if v_name = '' or char_length(v_name) > 60 or (v_desc is not null and char_length(v_desc) > 200)
     or not exists (select 1 from public.teams t where t.id = p_team_id) then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  begin
    insert into public.operational_roles (team_id, name, description, created_by)
      values (p_team_id, v_name, v_desc, v_uid) returning id into v_id;
  exception when unique_violation then
    return pg_catalog.jsonb_build_object('status', 'duplicate');
  end;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (p_team_id, v_uid, 'operational_role.created', 'operational_role', v_id,
            pg_catalog.jsonb_build_object('name', v_name));
  return pg_catalog.jsonb_build_object('status', 'created', 'id', v_id);
end;
$$;

-- Rename, re-describe, activate or deactivate. NULL means "unchanged"; an empty description clears it.
create or replace function public.update_operational_role(
  p_role_id uuid, p_name text default null, p_description text default null, p_is_active boolean default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid  uuid := auth.uid();
  v_role public.operational_roles%rowtype;
  v_name text;
  v_desc text;
begin
  select * into v_role from public.operational_roles r where r.id = p_role_id for update;
  if v_uid is null or not found or not private.has_permission(v_role.team_id, 'operational_roles.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  v_name := case when p_name is null then v_role.name else btrim(p_name) end;
  v_desc := case when p_description is null then v_role.description else nullif(btrim(p_description), '') end;
  if v_name = '' or char_length(v_name) > 60 or (v_desc is not null and char_length(v_desc) > 200) then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  begin
    update public.operational_roles r
      set name = v_name, description = v_desc, is_active = coalesce(p_is_active, r.is_active)
      where r.id = p_role_id;
  exception when unique_violation then
    return pg_catalog.jsonb_build_object('status', 'duplicate');
  end;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_role.team_id, v_uid, 'operational_role.updated', 'operational_role', p_role_id,
            pg_catalog.jsonb_build_object('previous_name', v_role.name, 'name', v_name,
                                          'is_active', coalesce(p_is_active, v_role.is_active)));
  return pg_catalog.jsonb_build_object('status', 'updated');
end;
$$;

-- Assign a role (several per member are allowed). p_is_primary marks it as the member's one
-- primary role and clears any other; calling again with false clears the flag on this role.
create or replace function public.assign_operational_role(
  p_membership_id uuid, p_role_id uuid, p_is_primary boolean default false)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.team_memberships%rowtype;
  v_r   public.operational_roles%rowtype;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'operational_roles.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  select * into v_r from public.operational_roles r where r.id = p_role_id;
  if not found or v_r.team_id <> v_m.team_id then
    raise exception 'invalid arguments' using errcode = '22023';
  end if;
  if v_m.membership_status <> 'approved' then
    return pg_catalog.jsonb_build_object('status', 'not_approved');
  end if;
  if not v_r.is_active then
    return pg_catalog.jsonb_build_object('status', 'role_inactive');
  end if;
  if coalesce(p_is_primary, false) then
    update public.member_operational_roles x set is_primary = false
      where x.membership_id = v_m.id and x.operational_role_id <> p_role_id and x.is_primary;
  end if;
  insert into public.member_operational_roles (membership_id, operational_role_id, is_primary, assigned_by)
    values (v_m.id, p_role_id, coalesce(p_is_primary, false), v_uid)
    on conflict (membership_id, operational_role_id) do update set is_primary = excluded.is_primary;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'operational_role.assigned', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('role_id', p_role_id, 'is_primary', coalesce(p_is_primary, false),
                                          'subject_user_id', v_m.user_id));
  return pg_catalog.jsonb_build_object('status', 'assigned');
end;
$$;

create or replace function public.unassign_operational_role(p_membership_id uuid, p_role_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_m   public.team_memberships%rowtype;
  v_n   integer;
begin
  select * into v_m from public.team_memberships m where m.id = p_membership_id for update;
  if v_uid is null or not found or not private.has_permission(v_m.team_id, 'operational_roles.manage') then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  perform private.require_aal2();
  delete from public.member_operational_roles x where x.membership_id = v_m.id and x.operational_role_id = p_role_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    return pg_catalog.jsonb_build_object('status', 'not_assigned');
  end if;
  insert into public.audit_logs (team_id, actor_user_id, action, entity_type, entity_id, metadata)
    values (v_m.team_id, v_uid, 'operational_role.unassigned', 'membership', v_m.id,
            pg_catalog.jsonb_build_object('role_id', p_role_id, 'subject_user_id', v_m.user_id));
  return pg_catalog.jsonb_build_object('status', 'unassigned');
end;
$$;

-- ---------------------------------------------------------------------------
-- Reads for approved members. Return data instead of opening table policies, so the
-- client-readable policy set does not grow and no e-mail address or user id is exposed.
-- ---------------------------------------------------------------------------
create or replace function public.list_operational_roles(p_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_manage boolean;
begin
  if auth.uid() is null or not (private.is_approved_member(p_team_id) or private.is_superadmin()) then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  v_manage := private.has_permission(p_team_id, 'operational_roles.manage');
  return (
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'id', r.id, 'name', r.name, 'description', r.description, 'is_active', r.is_active,
      'member_count', (select count(*) from public.member_operational_roles x
                         join public.team_memberships m on m.id = x.membership_id and m.membership_status = 'approved'
                        where x.operational_role_id = r.id)
    ) order by r.is_active desc, lower(r.name)), '[]'::jsonb)
    from public.operational_roles r
    where r.team_id = p_team_id and (r.is_active or v_manage));
end;
$$;

create or replace function public.team_directory(p_team_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if auth.uid() is null or not private.is_approved_member(p_team_id) then
    raise exception 'not permitted' using errcode = '42501';
  end if;
  return (
    select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'membership_id', m.id,
      'display_name', p.display_name,
      'organizational_title', p.organizational_title,
      'roles', (select coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
                          'id', r.id, 'name', r.name, 'is_primary', x.is_primary)
                        order by x.is_primary desc, lower(r.name)), '[]'::jsonb)
                from public.member_operational_roles x
                join public.operational_roles r on r.id = x.operational_role_id and r.is_active
                where x.membership_id = m.id)
    ) order by lower(coalesce(p.display_name, ''))), '[]'::jsonb)
    from public.team_memberships m
    left join public.profiles p on p.user_id = m.user_id
    where m.team_id = p_team_id and m.membership_status = 'approved');
end;
$$;

revoke execute on function
  public.create_operational_role(uuid, text, text),
  public.update_operational_role(uuid, text, text, boolean),
  public.assign_operational_role(uuid, uuid, boolean),
  public.unassign_operational_role(uuid, uuid),
  public.list_operational_roles(uuid),
  public.team_directory(uuid)
  from public, anon, service_role;
grant execute on function
  public.create_operational_role(uuid, text, text),
  public.update_operational_role(uuid, text, text, boolean),
  public.assign_operational_role(uuid, uuid, boolean),
  public.unassign_operational_role(uuid, uuid),
  public.list_operational_roles(uuid),
  public.team_directory(uuid)
  to authenticated;
