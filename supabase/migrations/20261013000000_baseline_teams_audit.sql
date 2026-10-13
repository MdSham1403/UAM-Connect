-- Phase 1b baseline: teams, audit_logs, internal helpers.
-- Scope is deliberately minimal (see DATABASE.md section 8). No membership, profile,
-- role, join-code or Superadmin objects belong here; they arrive in Phases 1c-1e.
--
-- Access model for this migration: RLS is ENABLED and NO client policy exists, and all
-- API roles (anon, authenticated, service_role) have every table privilege revoked.
-- Nothing in these tables is reachable through the Supabase API yet. Client-facing
-- policies are added with the memberships table (Phase 1d), not before.

-- ---------------------------------------------------------------------------
-- Internal schema: not exposed through the API (config.toml exposes only public).
-- No role is granted USAGE, so API clients cannot call anything in here.
-- ---------------------------------------------------------------------------
create schema if not exists private;
revoke all on schema private from public;
comment on schema private is
  'Internal helper functions. Not exposed through the API; no API role has USAGE.';

-- Trigger helper: keep updated_at consistent. SECURITY INVOKER, fixed empty search_path.
create or replace function private.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.updated_at := pg_catalog.now();
  return new;
end;
$$;

-- Validator used by a CHECK constraint: true only for a real IANA/PostgreSQL time zone.
create or replace function private.is_valid_timezone(tz text)
returns boolean
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if tz is null then
    return false;
  end if;
  perform pg_catalog.now() at time zone tz;
  return true;
exception when others then
  return false;
end;
$$;

-- Append-only guard for audit_logs (blocks UPDATE, DELETE and TRUNCATE).
create or replace function private.audit_logs_block_mutation()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only: % is not permitted', tg_op
    using errcode = 'insufficient_privilege';
end;
$$;

-- ---------------------------------------------------------------------------
-- teams
-- ---------------------------------------------------------------------------
create table public.teams (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  timezone    text not null default 'UTC',
  created_at  timestamptz not null default pg_catalog.now(),
  updated_at  timestamptz not null default pg_catalog.now(),
  constraint teams_name_not_blank check (btrim(name) <> '' and char_length(name) <= 100),
  constraint teams_timezone_valid check (private.is_valid_timezone(timezone))
);

-- One private team in v1; also prevents accidental duplicate team names.
create unique index teams_name_lower_key on public.teams (lower(name));

create trigger teams_set_updated_at
  before update on public.teams
  for each row execute function private.set_updated_at();

comment on table public.teams is
  'The private team. Single row in v1. RLS enabled, no client policy until Phase 1d.';

alter table public.teams enable row level security;
revoke all on table public.teams from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- audit_logs (append-only intent)
-- ---------------------------------------------------------------------------
create table public.audit_logs (
  id             uuid primary key default gen_random_uuid(),
  team_id        uuid not null references public.teams (id) on delete restrict,
  -- Deliberately NOT a foreign key to auth.users: deleting an account must never
  -- modify or block audit history (the table is append-only).
  actor_user_id  uuid,
  action         text not null,
  entity_type    text not null,
  entity_id      uuid,
  metadata       jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default pg_catalog.now(),
  constraint audit_logs_action_valid check (btrim(action) <> '' and char_length(action) <= 100),
  constraint audit_logs_entity_type_valid check (btrim(entity_type) <> '' and char_length(entity_type) <= 100),
  constraint audit_logs_metadata_object check (pg_catalog.jsonb_typeof(metadata) = 'object')
);

create index audit_logs_team_created_idx on public.audit_logs (team_id, created_at desc);

create trigger audit_logs_no_update_delete
  before update or delete on public.audit_logs
  for each row execute function private.audit_logs_block_mutation();

create trigger audit_logs_no_truncate
  before truncate on public.audit_logs
  for each statement execute function private.audit_logs_block_mutation();

comment on table public.audit_logs is
  'Append-only audit trail. RLS enabled, no client policy; written only by future privileged functions. Triggers block UPDATE/DELETE/TRUNCATE; the table owner or a superuser can still disable triggers (documented limitation).';

alter table public.audit_logs enable row level security;
revoke all on table public.audit_logs from public, anon, authenticated, service_role;
