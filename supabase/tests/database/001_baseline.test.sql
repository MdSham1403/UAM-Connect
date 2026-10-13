-- Phase 1b database tests (pgTAP). Run with: npm run db:test  (needs Docker + local Supabase)
-- These tests exercise the real database objects. They do not rely on seed data.
begin;
select plan(35);

-- 1. Objects exist --------------------------------------------------------------
select has_schema('private', 'private schema exists');
select has_table('public', 'teams', 'public.teams exists');
select has_table('public', 'audit_logs', 'public.audit_logs exists');

-- 2. RLS (SEC-22) -----------------------------------------------------------------
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity),
  0, 'SEC-22: every table in schema public has RLS enabled');
select is((select count(*)::int from pg_policies where schemaname = 'public'), 0,
  'no RLS policies exist yet (deny by default; client policies arrive in Phase 1d)');

-- 3. No API role holds any table or schema privilege ---------------------------------
select is(
  (select count(*)::int from unnest(array['anon','authenticated','service_role']) r,
        unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
    where has_table_privilege(r, 'public.teams', p)),
  0, 'anon/authenticated/service_role have no privilege on public.teams');
select is(
  (select count(*)::int from unnest(array['anon','authenticated','service_role']) r,
        unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
    where has_table_privilege(r, 'public.audit_logs', p)),
  0, 'anon/authenticated/service_role have no privilege on public.audit_logs');
select is(
  (select count(*)::int from unnest(array['anon','authenticated','service_role']) r
    where has_schema_privilege(r, 'private', 'USAGE')),
  0, 'no API role has USAGE on schema private');

-- 4. Functions: none SECURITY DEFINER, fixed search_path ----------------------------
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosecdef),
  0, 'no SECURITY DEFINER functions in public or private');
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and not ('search_path=""' = any (coalesce(p.proconfig, '{}')))),
  0, 'every private function pins an empty search_path');

-- 5. teams constraints ----------------------------------------------------------------
select lives_ok($$insert into public.teams (name) values ('Test Team A')$$, 'valid team inserts (default timezone UTC)');
select is((select timezone from public.teams where name = 'Test Team A'), 'UTC', 'timezone defaults to UTC');
select lives_ok($$insert into public.teams (name, timezone) values ('Test Team B', 'Asia/Kolkata')$$, 'valid IANA timezone accepted');
select throws_ok($$insert into public.teams (name) values ('   ')$$, '23514', null, 'blank team name rejected');
select throws_ok($$insert into public.teams (name) values (repeat('x', 101))$$, '23514', null, 'team name over 100 chars rejected');
select throws_ok($$insert into public.teams (name, timezone) values ('Test Team C', 'Mars/Phobos')$$, '23514', null, 'invalid timezone rejected');
select throws_ok($$insert into public.teams (name, timezone) values ('Test Team D', '')$$, '23514', null, 'empty timezone rejected');
select throws_ok($$insert into public.teams (name) values ('test team a')$$, '23505', null, 'case-insensitive duplicate name rejected');
select col_type_is('public', 'teams', 'created_at', 'timestamp with time zone', 'teams.created_at is timestamptz');
select col_type_is('public', 'teams', 'updated_at', 'timestamp with time zone', 'teams.updated_at is timestamptz');

-- updated_at is maintained by the trigger and cannot be set by the caller
update public.teams set updated_at = '2000-01-01T00:00:00Z' where name = 'Test Team A';
select ok((select updated_at > '2020-01-01T00:00:00Z' from public.teams where name = 'Test Team A'),
  'updated_at is maintained by trigger, not by the caller');

-- 6. audit_logs constraints and append-only behaviour ---------------------------------
select lives_ok(
  $$insert into public.audit_logs (team_id, action, entity_type, metadata)
    select id, 'test.event', 'team', '{"k":"v"}'::jsonb from public.teams where name = 'Test Team A'$$,
  'valid audit row inserts');
select col_type_is('public', 'audit_logs', 'created_at', 'timestamp with time zone', 'audit_logs.created_at is timestamptz');
select throws_ok(
  $$insert into public.audit_logs (team_id, action, entity_type) values (gen_random_uuid(), 'x', 'y')$$,
  '23503', null, 'audit row for a non-existent team rejected (FK)');
select throws_ok(
  $$insert into public.audit_logs (team_id, action, entity_type, metadata)
    select id, 'x', 'y', '[1]'::jsonb from public.teams where name = 'Test Team A'$$,
  '23514', null, 'non-object metadata rejected');
select throws_ok(
  $$insert into public.audit_logs (team_id, action, entity_type)
    select id, '  ', 'y' from public.teams where name = 'Test Team A'$$,
  '23514', null, 'blank audit action rejected');
select throws_ok($$update public.audit_logs set action = 'tampered'$$, '42501', null, 'audit UPDATE blocked');
select throws_ok($$delete from public.audit_logs$$, '42501', null, 'audit DELETE blocked');
select throws_ok($$truncate public.audit_logs$$, '42501', null, 'audit TRUNCATE blocked');
select throws_ok($$delete from public.teams where name = 'Test Team A'$$, '23503', null,
  'a team with audit history cannot be deleted (ON DELETE RESTRICT)');

-- 7. Behaviour as untrusted roles ------------------------------------------------------
set local role anon;
select throws_ok($$select * from public.teams$$, '42501', null, 'anon cannot read teams');
select throws_ok($$select * from public.audit_logs$$, '42501', null, 'anon cannot read audit_logs');
reset role;
set local role authenticated;
select throws_ok($$select * from public.teams$$, '42501', null, 'authenticated cannot read teams (no grant, no policy)');
select throws_ok($$insert into public.audit_logs (team_id, action, entity_type) values (gen_random_uuid(), 'x', 'y')$$,
  '42501', null, 'authenticated cannot write audit_logs');
select throws_ok($$update public.teams set name = 'hijack'$$, '42501', null, 'authenticated cannot update teams');
reset role;

select * from finish();
rollback;
