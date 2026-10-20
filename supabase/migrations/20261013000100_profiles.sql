-- Phase 1c: basic profiles.
-- A profile is the user's OWN record (display name and self-declared organizational title).
-- It carries no privilege: nothing here is ever used for authorization, and having a
-- profile does NOT make anyone a team member. Rows are not created at signup; the user
-- creates their own profile after signing in (Phase 1d's join function will also
-- upsert it). Teammate visibility policies are added in Phase 1d with memberships.

create table public.profiles (
  user_id               uuid primary key references auth.users (id) on delete cascade,
  display_name          text not null,
  organizational_title  text,
  created_at            timestamptz not null default pg_catalog.now(),
  updated_at            timestamptz not null default pg_catalog.now(),
  constraint profiles_display_name_valid
    check (btrim(display_name) <> '' and char_length(display_name) <= 80),
  constraint profiles_title_valid
    check (organizational_title is null
           or (btrim(organizational_title) <> '' and char_length(organizational_title) <= 100))
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function private.set_updated_at();

comment on table public.profiles is
  'Own-profile data only. Self-declared; never an authorization input. Own-row RLS; teammate read policy arrives in Phase 1d.';

alter table public.profiles enable row level security;

-- Start from nothing, then grant the minimum (column-level for writes).
revoke all on table public.profiles from public, anon, authenticated, service_role;
grant select on table public.profiles to authenticated;
grant insert (user_id, display_name, organizational_title) on table public.profiles to authenticated;
grant update (display_name, organizational_title) on table public.profiles to authenticated;
-- No DELETE or TRUNCATE for clients; user_id, created_at and updated_at are not client-writable.

create policy profiles_select_own on public.profiles
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy profiles_insert_own on public.profiles
  for insert to authenticated
  with check (user_id = (select auth.uid()));

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
