-- STAND-IN for the Supabase pieces the migrations and verify.sql touch. Used ONLY by the CI
-- database job on a plain PostgreSQL service container. It is NOT Supabase: on a real
-- project these roles, the auth schema and the default privileges already exist.
-- Stub of the Supabase pieces the baseline touches (NOT Supabase itself).
do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin noinherit; end if;
  if not exists (select 1 from pg_roles where rolname='service_role') then create role service_role nologin noinherit bypassrls; end if;
end $$;
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
-- Supabase grants new public tables/functions to API roles by default; replicate that
-- so the migration's explicit REVOKEs are actually exercised.
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on functions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
-- auth stub: minimal users table and uid() reading JWT claims like Supabase does
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$f$;
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to anon, authenticated, service_role;
alter table auth.users add column if not exists email_confirmed_at timestamptz;
create or replace function auth.jwt() returns jsonb language sql stable as $f$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$f$;
grant execute on function auth.jwt() to anon, authenticated, service_role;
