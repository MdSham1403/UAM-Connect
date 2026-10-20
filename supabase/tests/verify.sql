-- Database verification (no Docker, no extensions). ONE statement, so it runs through
--   npx supabase db query --linked -f supabase/tests/verify.sql      (hosted dev project)
-- or pasted into the Supabase dashboard SQL editor, or psql.
--
-- It creates temporary fixtures, runs every check, then ALWAYS ends by raising an
-- exception whose message is the report. That makes the database roll back every fixture,
-- so nothing persists. The CLI will therefore print "failed to execute query"; that is
-- intentional. Read the first line of the message: "VERIFY RESULT: PASS" or "FAIL".
-- Requires a role that can SET ROLE to anon/authenticated (postgres on Supabase).
do $verify$
declare
  c        record;
  ok       boolean;
  got      text;
  n_pass   int := 0;
  n_fail   int := 0;
  report   text := '';
  team_a   uuid;
  team_b   uuid;
begin
  -- Fixtures (rolled back at the end) ------------------------------------------------
  insert into public.teams (name) values ('verify-team-a') returning id into team_a;
  insert into public.teams (name) values ('verify-team-b') returning id into team_b;
  perform set_config('verify.team_a', team_a::text, true);
  perform set_config('verify.team_b', team_b::text, true);
  insert into public.audit_logs (team_id, action, entity_type) values (team_a, 'verify.event', 'team');
  insert into auth.users (id, email, email_confirmed_at) values
    ('11111111-1111-4111-8111-111111111111', 'ua@example.invalid', now()), ('22222222-2222-4222-8222-222222222222', 'ub@example.invalid', now()),
    ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'admin@example.invalid', now()), ('a2a2a2a2-a2a2-4a2a-8a2a-a2a2a2a2a2a2', 'admin2@example.invalid', now()),
    ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'member@example.invalid', now()), ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'new@example.invalid', now()),
    ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'unconfirmed@example.invalid', null), ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'new2@example.invalid', now()),
    ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'new3@example.invalid', now()), ('12121212-1212-4212-8212-121212121212', 'stranger@example.invalid', now()),
    ('33333333-3333-4333-8333-333333333333', 'selfadmin@example.invalid', now()), ('44444444-4444-4444-8444-444444444444', 'badmin@example.invalid', now()),
    ('55555555-5555-4555-8555-555555555555', 'buser@example.invalid', now()),
    ('66666666-6666-4666-8666-666666666666', 'superadmin@example.invalid', now()), ('77777777-7777-4777-8777-777777777777', 'superadmin2@example.invalid', now()),
    ('88888888-8888-4888-8888-888888888888', 'teamlead@example.invalid', now()), ('99999999-9999-4999-8999-999999999999', 'suspended@example.invalid', now());
  insert into public.profiles (user_id, display_name) values ('22222222-2222-4222-8222-222222222222', 'Verify B');
  -- Approved members and their bundles (the Admin role cannot be granted by any function
  -- yet, so Admin fixtures are inserted directly as the table owner).
  insert into public.team_memberships (team_id, user_id, membership_status, approved_at) values
    (team_a, 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'approved', now()), (team_a, 'a2a2a2a2-a2a2-4a2a-8a2a-a2a2a2a2a2a2', 'approved', now()),
    (team_a, 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'approved', now()), (team_a, '33333333-3333-4333-8333-333333333333', 'approved', now()),
    (team_b, '44444444-4444-4444-8444-444444444444', 'approved', now());
  insert into public.team_memberships (team_id, user_id, membership_status) values (team_b, '55555555-5555-4555-8555-555555555555', 'pending');
  insert into public.member_app_roles (membership_id, app_role_id)
    select m.id, a.id from public.team_memberships m
    join public.app_roles a on a.team_id = m.team_id and a.key = 'admin'
    where m.user_id in ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'a2a2a2a2-a2a2-4a2a-8a2a-a2a2a2a2a2a2', '33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444');
  insert into public.member_app_roles (membership_id, app_role_id)
    select m.id, a.id from public.team_memberships m
    join public.app_roles a on a.team_id = m.team_id and a.key = 'member'
    where m.user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  insert into public.team_memberships (team_id, user_id, membership_status, approved_at, suspended_at) values
    (team_a, '88888888-8888-4888-8888-888888888888', 'approved', now(), null), (team_a, '99999999-9999-4999-8999-999999999999', 'suspended', now(), now());
  insert into public.member_app_roles (membership_id, app_role_id)
    select m.id, a.id from public.team_memberships m
    join public.app_roles a on a.team_id = m.team_id and a.key = 'team_lead'
    where m.user_id = '88888888-8888-4888-8888-888888888888';
  -- A SUSPENDED member who still holds the Admin role: suspension must remove every permission.
  insert into public.member_app_roles (membership_id, app_role_id)
    select m.id, a.id from public.team_memberships m
    join public.app_roles a on a.team_id = m.team_id and a.key = 'admin'
    where m.user_id = '99999999-9999-4999-8999-999999999999';
  insert into public.join_requests (team_id, user_id, status) values
    (team_a, '33333333-3333-4333-8333-333333333333', 'pending'), (team_b, '55555555-5555-4555-8555-555555555555', 'pending');
  perform set_config('verify.mem_a',  (select id::text from public.team_memberships where user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'), true);
  perform set_config('verify.mem_a2', (select id::text from public.team_memberships where user_id = 'a2a2a2a2-a2a2-4a2a-8a2a-a2a2a2a2a2a2'), true);
  perform set_config('verify.mem_m',  (select id::text from public.team_memberships where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'), true);
  perform set_config('verify.req_sa', (select id::text from public.join_requests where user_id = '33333333-3333-4333-8333-333333333333'), true);
  perform set_config('verify.req_bu', (select id::text from public.join_requests where user_id = '55555555-5555-4555-8555-555555555555'), true);
  -- Known fixture codes (raw values are 18-19 uppercase letters/digits).
  insert into public.join_codes (team_id, code_hash, label, expires_at, max_uses, use_count, created_at, revoked_at) values
    (team_a, encode(sha256(convert_to('VALIDCODEFIXTURE01', 'UTF8')), 'hex'), 'fixture-valid', now() + interval '7 days', 5, 0, now(), null),
    (team_a, encode(sha256(convert_to('EXPIREDFIXTURECODE1', 'UTF8')), 'hex'), 'fixture-expired', now() - interval '1 day', 5, 0, now() - interval '2 days', null),
    (team_a, encode(sha256(convert_to('REVOKEDFIXTURECODE1', 'UTF8')), 'hex'), 'fixture-revoked', now() + interval '7 days', 5, 0, now(), now()),
    (team_a, encode(sha256(convert_to('EXHAUSTEDFIXTURE001', 'UTF8')), 'hex'), 'fixture-exhausted', now() + interval '7 days', 1, 1, now(), null);

  -- Phase 2a fixtures: two ordinary approved members for the operational-role tests.
  insert into auth.users (id, email, email_confirmed_at) values
    ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'roleone@example.invalid', now()), ('c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2', 'roletwo@example.invalid', now());
  insert into public.team_memberships (team_id, user_id, membership_status, approved_at) values
    (team_a, 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'approved', now()), (team_a, 'c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2', 'approved', now());
  insert into public.member_app_roles (membership_id, app_role_id)
    select m.id, a.id from public.team_memberships m join public.app_roles a on a.team_id = m.team_id and a.key = 'member'
    where m.user_id in ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2');
  insert into public.profiles (user_id, display_name, organizational_title) values
    ('c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'Role One', 'UAM Engineer'), ('c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2', 'Role Two', null);
  insert into auth.users (id, email, email_confirmed_at) values ('d1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', 'pendingperson@example.invalid', now());
  insert into public.team_memberships (team_id, user_id, membership_status) values (team_a, 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', 'pending');
  insert into public.profiles (user_id, display_name) values ('d1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', 'Pending Person');
  perform set_config('verify.mem_pp', (select id::text from public.team_memberships where user_id = 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1'), true);
  perform set_config('verify.mem_sus2', (select id::text from public.team_memberships where user_id = '99999999-9999-4999-8999-999999999999'), true);
  perform set_config('verify.mem_r1', (select id::text from public.team_memberships where user_id = 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1'), true);
  perform set_config('verify.mem_r2', (select id::text from public.team_memberships where user_id = 'c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2'), true);

  -- Structural checks: each query must return true -------------------------------------
  for c in select * from (values
    ('private schema exists'::text, $s$select exists (select 1 from pg_namespace where nspname = 'private')$s$::text),
    ('all expected tables exist', $s$select (select count(*) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and c.relname in ('teams','audit_logs','profiles','team_memberships','app_roles','member_app_roles','join_codes','join_requests','rate_limit_events','platform_owners','operational_roles','member_operational_roles')) = 12$s$),
    ('SEC-22: every table in public has RLS enabled', $s$select not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity)$s$),
    ('policy set is exactly the ten expected policies', $s$select (select array_agg(policyname::text order by policyname::text collate "C") from pg_policies where schemaname = 'public') = array['join_codes_select_managers','join_requests_select_own','join_requests_select_reviewers','profiles_insert_own','profiles_select_own','profiles_select_reviewers','profiles_update_own','team_memberships_select_own','team_memberships_select_reviewers','teams_select_member']$s$),
    ('every policy targets only role authenticated', $s$select not exists (select 1 from pg_policies where schemaname = 'public' and roles <> array['authenticated']::name[])$s$),
    ('no unconditional policy (true)', $s$select not exists (select 1 from pg_policies where schemaname = 'public' and (btrim(coalesce(qual,'')) in ('true','(true)') or btrim(coalesce(with_check,'')) in ('true','(true)')))$s$),
    ('anon and service_role hold no privilege on any public table', $s$select not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace, unnest(array['anon','service_role']) r where n.nspname = 'public' and c.relkind = 'r' and (has_table_privilege(r, c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') or has_any_column_privilege(r, c.oid, 'SELECT,INSERT,UPDATE,REFERENCES')))$s$),
    ('authenticated holds no table-level write, delete, truncate, trigger or references privilege anywhere', $s$select not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and has_table_privilege('authenticated', c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'))$s$),
    ('authenticated has table-level SELECT only on profiles', $s$select (select array_agg(c.relname::text order by c.relname::text) from pg_class c join pg_namespace n on n.oid = c.relnamespace where n.nspname = 'public' and c.relkind = 'r' and has_table_privilege('authenticated', c.oid, 'SELECT')) = array['profiles']$s$),
    ('authenticated column-level INSERT/UPDATE is exactly the profile fields', $s$select (select array_agg(x order by x collate "C") from (select c.relname || '.' || a.attname || ':' || p as x from pg_class c join pg_namespace n on n.oid = c.relnamespace join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped cross join unnest(array['INSERT','UPDATE']) p where n.nspname = 'public' and c.relkind = 'r' and has_column_privilege('authenticated', c.oid, a.attnum, p)) s) = array['profiles.display_name:INSERT','profiles.display_name:UPDATE','profiles.organizational_title:INSERT','profiles.organizational_title:UPDATE','profiles.user_id:INSERT']$s$),
    ('authenticated cannot select sensitive columns', $s$select not has_column_privilege('authenticated','public.team_memberships','approved_by','SELECT') and not has_column_privilege('authenticated','public.join_requests','join_code_id','SELECT') and not has_column_privilege('authenticated','public.join_requests','reviewed_by','SELECT') and not has_column_privilege('authenticated','public.teams','created_at','SELECT') and not has_column_privilege('authenticated','public.join_codes','code_hash','SELECT') and not has_column_privilege('authenticated','public.join_codes','created_by','SELECT') and not has_column_privilege('authenticated','public.join_codes','revoked_by','SELECT')$s$),
    ('authenticated has no access at all to roles, role grants, rate limits, audit or platform owners', $s$select not exists (select 1 from unnest(array['app_roles','member_app_roles','rate_limit_events','audit_logs','platform_owners','operational_roles','member_operational_roles']) t where has_any_column_privilege('authenticated', ('public.' || t)::regclass, 'SELECT,INSERT,UPDATE,REFERENCES')) and not has_any_column_privilege('authenticated', 'public.join_codes'::regclass, 'INSERT,UPDATE,REFERENCES')$s$),
    ('private schema: no USAGE for anon/service_role; USAGE for authenticated (policy helper)', $s$select not has_schema_privilege('anon','private','USAGE') and not has_schema_privilege('service_role','private','USAGE') and has_schema_privilege('authenticated','private','USAGE')$s$),
    ('SECURITY DEFINER functions are exactly the reviewed list', $s$select (select array_agg(n.nspname || '.' || p.proname order by (n.nspname || '.' || p.proname) collate "C") from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and p.prosecdef) = array['private.can_review_user','private.has_permission','private.is_approved_member','private.is_superadmin','public.assign_operational_role','public.create_join_code','public.create_operational_role','public.get_my_access','public.grant_app_role','public.list_operational_roles','public.redeem_join_code','public.reinstate_member','public.review_join_request','public.revoke_app_role','public.revoke_join_code','public.suspend_member','public.team_directory','public.unassign_operational_role','public.update_operational_role']$s$),
    ('every function in public and private pins an empty search_path', $s$select not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and not ('search_path=""' = any (coalesce(p.proconfig, '{}'))))$s$),
    ('anon and service_role cannot execute any function in public or private', $s$select not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace, unnest(array['anon','service_role']) r where n.nspname in ('public','private') and has_function_privilege(r, p.oid, 'EXECUTE'))$s$),
    ('authenticated can execute exactly the 15 RPCs and the 3 policy helpers', $s$select (select array_agg(n.nspname || '.' || p.proname order by (n.nspname || '.' || p.proname) collate "C") from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname in ('public','private') and has_function_privilege('authenticated', p.oid, 'EXECUTE')) = array['private.can_review_user','private.has_permission','private.is_approved_member','public.assign_operational_role','public.create_join_code','public.create_operational_role','public.get_my_access','public.grant_app_role','public.list_operational_roles','public.redeem_join_code','public.reinstate_member','public.review_join_request','public.revoke_app_role','public.revoke_join_code','public.suspend_member','public.team_directory','public.unassign_operational_role','public.update_operational_role']$s$),
    ('all *_at columns in public are timestamptz', $s$select not exists (select 1 from information_schema.columns where table_schema = 'public' and column_name like '%\_at' and data_type <> 'timestamp with time zone')$s$),
    ('audit_logs append-only triggers exist and are enabled', $s$select (select count(*) from pg_trigger where tgrelid = 'public.audit_logs'::regclass and tgname in ('audit_logs_no_update_delete','audit_logs_no_truncate') and tgenabled = 'O') = 2$s$),
    ('join_codes has no raw-code column', $s$select not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'join_codes' and column_name in ('code','raw_code'))$s$),
    ('fixed role bundles seeded for a new team (Admin has 5 keys; Member and Team Lead none)', $s$select (select count(*) from public.app_roles where team_id = current_setting('verify.team_a')::uuid) = 3 and (select jsonb_array_length(permissions) from public.app_roles where team_id = current_setting('verify.team_a')::uuid and key = 'admin') = 5 and (select count(*) from public.app_roles where team_id = current_setting('verify.team_a')::uuid and key in ('member','team_lead') and jsonb_array_length(permissions) = 0) = 2$s$),
    ('bootstrap_superadmin is executable by no API role (only the owner role)', $s$select not has_function_privilege('anon','private.bootstrap_superadmin(uuid,uuid,text,boolean)','EXECUTE') and not has_function_privilege('authenticated','private.bootstrap_superadmin(uuid,uuid,text,boolean)','EXECUTE') and not has_function_privilege('service_role','private.bootstrap_superadmin(uuid,uuid,text,boolean)','EXECUTE')$s$),
    ('platform_owners guard trigger exists and is enabled', $s$select (select count(*) from pg_trigger where tgrelid = 'public.platform_owners'::regclass and tgname = 'platform_owners_guard' and tgenabled = 'O') = 1$s$),
    ('operational_roles: six initial roles seeded for a new team'::text, $s$select (select count(*) from public.operational_roles where team_id = current_setting('verify.team_a')::uuid) = 6$s$::text),
    ('operational_roles: a member has at most one primary role (partial unique index)', $s$select exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'member_operational_roles_one_primary_key' and indexdef ilike '%where%is_primary%')$s$),
    ('operational_roles: roles cannot be deleted while assigned (restrict, no cascade)', $s$select exists (select 1 from pg_constraint c where c.conrelid = 'public.member_operational_roles'::regclass and c.confrelid = 'public.operational_roles'::regclass and c.confdeltype = 'r')$s$)
  ) as t(name, q) loop
    begin
      execute c.q into ok;
    exception when others then
      ok := false;
    end;
    if coalesce(ok, false) then n_pass := n_pass + 1; report := report || E'PASS  ' || c.name || E'\n';
    else n_fail := n_fail + 1; report := report || E'FAIL  ' || c.name || E'\n'; end if;
  end loop;

  -- Behavioural checks: (name, role, jwt sub, aal, sql, expectation) ----------------------
  -- expectation: 'OK' (no error) | SQLSTATE code | 'VALUE:x' (single-value result equals x)
  for c in select * from (values
    ('teams: blank name rejected'::text, null::text, null::text, null::text, $s$insert into public.teams (name) values ('   ')$s$::text, '23514'::text),
    ('teams: name over 100 chars rejected', null, null, null, $s$insert into public.teams (name) values (repeat('x',101))$s$, '23514'),
    ('teams: invalid timezone rejected', null, null, null, $s$insert into public.teams (name, timezone) values ('verify-bad-tz','Mars/Phobos')$s$, '23514'),
    ('teams: valid timezone accepted', null, null, null, $s$insert into public.teams (name, timezone) values ('verify-c','Asia/Kolkata')$s$, 'OK'),
    ('teams: case-insensitive duplicate name rejected', null, null, null, $s$insert into public.teams (name) values ('VERIFY-TEAM-A')$s$, '23505'),
    ('teams: updated_at maintained by trigger', null, null, null, $s$with u as (update public.teams set updated_at = '2000-01-01T00:00:00Z' where name = 'verify-team-a' returning updated_at) select (select updated_at > '2020-01-01T00:00:00Z' from u)::text$s$, 'VALUE:true'),
    ('audit_logs: valid insert accepted', null, null, null, $s$insert into public.audit_logs (team_id, action, entity_type, metadata) values (current_setting('verify.team_a')::uuid, 'x', 'y', '{"k":1}')$s$, 'OK'),
    ('audit_logs: non-object metadata rejected', null, null, null, $s$insert into public.audit_logs (team_id, action, entity_type, metadata) values (current_setting('verify.team_a')::uuid, 'x', 'y', '[1]')$s$, '23514'),
    ('audit_logs: unknown team rejected', null, null, null, $s$insert into public.audit_logs (team_id, action, entity_type) values (gen_random_uuid(), 'x', 'y')$s$, '23503'),
    ('audit_logs: UPDATE blocked', null, null, null, $s$update public.audit_logs set action = 'tampered'$s$, '42501'),
    ('audit_logs: DELETE blocked', null, null, null, $s$delete from public.audit_logs$s$, '42501'),
    ('audit_logs: TRUNCATE blocked', null, null, null, $s$truncate public.audit_logs$s$, '42501'),
    ('teams: team with audit history cannot be deleted', null, null, null, $s$delete from public.teams where name = 'verify-team-a'$s$, '23503'),
    ('anon cannot read teams', 'anon', null, null, $s$select * from public.teams$s$, '42501'),
    ('anon cannot read audit_logs', 'anon', null, null, $s$select * from public.audit_logs$s$, '42501'),
    ('anon cannot read profiles', 'anon', null, null, $s$select * from public.profiles$s$, '42501'),
    ('anon cannot read team_memberships', 'anon', null, null, $s$select id from public.team_memberships$s$, '42501'),
    ('anon cannot insert profiles', 'anon', null, null, $s$insert into public.profiles (user_id, display_name) values (gen_random_uuid(), 'x')$s$, '42501'),
    ('non-member sees no teams (column-granted select, policy denies)', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:0'),
    ('authenticated cannot select * from teams (ungranted columns)', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select * from public.teams$s$, '42501'),
    ('authenticated cannot update teams', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$update public.teams set name = 'hijack'$s$, '42501'),
    ('authenticated cannot read audit_logs', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select * from public.audit_logs$s$, '42501'),
    ('authenticated cannot write audit_logs', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$insert into public.audit_logs (team_id, action, entity_type) values (gen_random_uuid(), 'x', 'y')$s$, '42501'),
    ('profiles: user sees only own row', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$select count(*)::text from public.profiles$s$, 'VALUE:0'),
    ('profiles: user can create own profile', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$insert into public.profiles (user_id, display_name, organizational_title) values ('11111111-1111-4111-8111-111111111111', 'Verify A', 'UAM Engineer')$s$, 'OK'),
    ('profiles: user cannot create a profile for someone else', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$insert into public.profiles (user_id, display_name) values (gen_random_uuid(), 'impostor')$s$, '42501'),
    ('profiles: user cannot overwrite another user''s row', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$with u as (update public.profiles set display_name = 'hijacked' where user_id = '22222222-2222-4222-8222-222222222222' returning 1) select count(*)::text from u$s$, 'VALUE:0'),
    ('profiles: user can update own display name', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$with u as (update public.profiles set display_name = 'Verify A2' where user_id = '11111111-1111-4111-8111-111111111111' returning 1) select count(*)::text from u$s$, 'VALUE:1'),
    ('profiles: user cannot change user_id', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$update public.profiles set user_id = gen_random_uuid() where user_id = '11111111-1111-4111-8111-111111111111'$s$, '42501'),
    ('profiles: user cannot delete own profile', 'authenticated', '11111111-1111-4111-8111-111111111111', 'aal1', $s$delete from public.profiles where user_id = '11111111-1111-4111-8111-111111111111'$s$, '42501'),
    ('profiles: other user still sees only own row', 'authenticated', '22222222-2222-4222-8222-222222222222', 'aal1', $s$select count(*)::text from public.profiles$s$, 'VALUE:1'),
    ('profiles: blank display name rejected', 'authenticated', '22222222-2222-4222-8222-222222222222', 'aal1', $s$update public.profiles set display_name = '  ' where user_id = '22222222-2222-4222-8222-222222222222'$s$, '23514'),
    ('profiles: display name over 80 chars rejected', 'authenticated', '22222222-2222-4222-8222-222222222222', 'aal1', $s$update public.profiles set display_name = repeat('x',81) where user_id = '22222222-2222-4222-8222-222222222222'$s$, '23514'),
    ('profiles: blank title rejected', 'authenticated', '22222222-2222-4222-8222-222222222222', 'aal1', $s$update public.profiles set organizational_title = ' ' where user_id = '22222222-2222-4222-8222-222222222222'$s$, '23514'),
    ('app_roles: unknown permission key rejected', null, null, null, $s$update public.app_roles set permissions = '["superpower"]' where team_id = current_setting('verify.team_a')::uuid and key = 'member'$s$, '23514'),
    ('join_codes: use_count above max_uses rejected', null, null, null, $s$insert into public.join_codes (team_id, code_hash, expires_at, max_uses, use_count) values (current_setting('verify.team_a')::uuid, 'h-bad', now() + interval '1 day', 1, 2)$s$, '23514'),
    ('team_memberships: invalid status rejected', null, null, null, $s$update public.team_memberships set membership_status = 'superuser' where user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$s$, '23514'),
    ('join_requests: second pending request for the same user is rejected', null, null, null, $s$insert into public.join_requests (team_id, user_id, status) values (current_setting('verify.team_a')::uuid, '33333333-3333-4333-8333-333333333333', 'pending')$s$, '23505'),
    ('anon cannot call redeem_join_code', 'anon', null, null, $s$select public.redeem_join_code('ABCDEFGHIJKLMNOP','x')$s$, '42501'),
    ('unconfirmed email cannot redeem', 'authenticated', 'dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'aal1', $s$select public.redeem_join_code('ABCDEFGHIJKLMNOP','Unconfirmed')$s$, '42501'),
    ('invalid code returns a generic status', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.redeem_join_code('NOTAREALCODE12345','Stranger')->>'status'$s$, 'VALUE:invalid_code'),
    ('failed attempt is recorded (committed, not rolled back)', null, null, null, $s$select count(*)::text from public.rate_limit_events where action = 'join_code_failed' and user_id = '12121212-1212-4212-8212-121212121212'$s$, 'VALUE:1'),
    ('expired code is indistinguishable from invalid', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.redeem_join_code('EXPIREDFIXTURECODE1','Stranger')->>'status'$s$, 'VALUE:invalid_code'),
    ('revoked code is indistinguishable from invalid', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.redeem_join_code('REVOKEDFIXTURECODE1','Stranger')->>'status'$s$, 'VALUE:invalid_code'),
    ('exhausted code is indistinguishable from invalid', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.redeem_join_code('EXHAUSTEDFIXTURE001','Stranger')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: wrong guess 1 of 5 returns invalid_code', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('WRONGGUESSCODE01','Guesser')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: wrong guess 2 of 5 returns invalid_code', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('WRONGGUESSCODE02','Guesser')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: wrong guess 3 of 5 returns invalid_code', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('WRONGGUESSCODE03','Guesser')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: wrong guess 4 of 5 returns invalid_code', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('WRONGGUESSCODE04','Guesser')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: wrong guess 5 of 5 returns invalid_code', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('WRONGGUESSCODE05','Guesser')->>'status'$s$, 'VALUE:invalid_code'),
    ('rate limit: after 5 failures even a VALID code is refused', 'authenticated', 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'aal1', $s$select public.redeem_join_code('VALIDCODEFIXTURE01','Guesser')->>'status'$s$, 'VALUE:rate_limited'),
    ('rate limit: refused attempt did not consume the code', null, null, null, $s$select use_count::text from public.join_codes where label = 'fixture-valid'$s$, 'VALUE:0'),
    ('create code: admin without MFA (aal1) refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 3, 7, 'verify')$s$, '42501'),
    ('create code: plain member refused', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 3, 7, 'verify')$s$, '42501'),
    ('create code: invalid arguments refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 999, 7, 'verify')$s$, '22023'),
    ('create code: admin with MFA succeeds (code kept in a session variable)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select set_config('verify.code', public.create_join_code(current_setting('verify.team_a')::uuid, 3, 7, 'verify')->>'code', true)$s$, 'OK'),
    ('create code: only a hash is stored (raw value is not in join_codes)', null, null, null, $s$select count(*)::text from public.join_codes where code_hash = current_setting('verify.code') or label = current_setting('verify.code')$s$, 'VALUE:0'),
    ('create code: the stored hash matches the normalized raw code', null, null, null, $s$select count(*)::text from public.join_codes where code_hash = encode(sha256(convert_to(upper(regexp_replace(current_setting('verify.code'), '[^A-Za-z0-9]', '', 'g')), 'UTF8')), 'hex') and label = 'verify'$s$, 'VALUE:1'),
    ('create code: raw code is 20 hex characters (80 bits) shown in groups', null, null, null, $s$select (current_setting('verify.code') ~ '^[0-9A-F]{5}(-[0-9A-F]{5}){3}$')::text$s$, 'VALUE:true'),
    ('redeem: lowercase code with dashes is accepted and creates a PENDING membership', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select public.redeem_join_code(lower(current_setting('verify.code')), '  New Person ', 'UAM Engineer')->>'status'$s$, 'VALUE:pending'),
    ('setup: remember the request id of the new person', null, null, null, $s$select set_config('verify.req_n', (select id from public.join_requests where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc' and status = 'pending')::text, true)$s$, 'OK'),
    ('redeem: the use was counted', null, null, null, $s$select use_count::text from public.join_codes where label = 'verify'$s$, 'VALUE:1'),
    ('redeem: profile was written from the validated input', null, null, null, $s$select display_name from public.profiles where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:New Person'),
    ('redeem: membership is pending, not approved', null, null, null, $s$select membership_status from public.team_memberships where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:pending'),
    ('redeem: user can read own membership status', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select membership_status from public.team_memberships where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:pending'),
    ('redeem: pending user sees no teams', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:0'),
    ('redeem: pending user sees only own membership row', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(id)::text from public.team_memberships$s$, 'VALUE:1'),
    ('redeem: redeeming again returns already_pending and consumes nothing', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select public.redeem_join_code(current_setting('verify.code'), 'New Person')->>'status'$s$, 'VALUE:already_pending'),
    ('redeem: use count unchanged by the repeat', null, null, null, $s$select use_count::text from public.join_codes where label = 'verify'$s$, 'VALUE:1'),
    ('review: pending user cannot approve (even their own request)', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')$s$, '42501'),
    ('review: admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')$s$, '42501'),
    ('review: plain member refused', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')$s$, '42501'),
    ('review: admin cannot review their OWN request (self-approval)', 'authenticated', '33333333-3333-4333-8333-333333333333', 'aal2', $s$select public.review_join_request(current_setting('verify.req_sa')::uuid, 'approve')$s$, '42501'),
    ('review: admin of another team cannot review this team''s request', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')$s$, '42501'),
    ('review: admin cannot review another team''s request', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.review_join_request(current_setting('verify.req_bu')::uuid, 'approve')$s$, '42501'),
    ('review: unknown request id and no permission look the same', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select public.review_join_request(gen_random_uuid(), 'approve')$s$, '42501'),
    ('review: invalid decision refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'maybe')$s$, '22023'),
    ('review: admin with MFA approves', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')->>'status'$s$, 'VALUE:approved'),
    ('review: approving twice is a no-op', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n')::uuid, 'approve')->>'status'$s$, 'VALUE:not_pending'),
    ('approved user now sees their team', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:1'),
    ('approved user still sees only their own membership row', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(id)::text from public.team_memberships$s$, 'VALUE:1'),
    ('approved user holds the Member bundle only', null, null, null, $s$select string_agg(a.key, ',' order by a.key) from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id join public.team_memberships m on m.id = r.membership_id where m.user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:member'),
    ('reject flow: user redeems and is pending', 'authenticated', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'aal1', $s$select public.redeem_join_code(current_setting('verify.code'), 'Third Person')->>'status'$s$, 'VALUE:pending'),
    ('setup: remember request and membership ids of the third person', null, null, null, $s$select set_config('verify.req_n3', (select id from public.join_requests where user_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff' and status = 'pending')::text, true)$s$, 'OK'),
    ('setup: remember membership id of the third person', null, null, null, $s$select set_config('verify.mem_n3', (select id from public.team_memberships where user_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff')::text, true)$s$, 'OK'),
    ('reject flow: admin rejects', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n3')::uuid, 'reject')->>'status'$s$, 'VALUE:rejected'),
    ('reject flow: rejected user sees no teams', 'authenticated', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:0'),
    ('reject flow: rejected user may re-apply with a valid code', 'authenticated', 'ffffffff-ffff-4fff-8fff-ffffffffffff', 'aal1', $s$select public.redeem_join_code(current_setting('verify.code'), 'Third Person')->>'status'$s$, 'VALUE:pending'),
    ('reject flow: the code is now exhausted (3 of 3)', null, null, null, $s$select use_count::text from public.join_codes where label = 'verify'$s$, 'VALUE:3'),
    ('suspend: admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.suspend_member(current_setting('verify.mem_m')::uuid)$s$, '42501'),
    ('suspend: plain member refused', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_m')::uuid)$s$, '42501'),
    ('suspend: admin cannot suspend themselves', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_a')::uuid)$s$, '42501'),
    ('suspend: admin cannot suspend another Admin (needs Superadmin, Phase 1e)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_a2')::uuid)$s$, '42501'),
    ('suspend: admin with MFA suspends a member', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_m')::uuid, 'verify')->>'status'$s$, 'VALUE:suspended'),
    ('suspend: effect is immediate (suspended user sees no teams)', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:0'),
    ('suspend: admin creates a second code', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select set_config('verify.code2', public.create_join_code(current_setting('verify.team_a')::uuid, 5, 7, 'verify2')->>'code', true)$s$, 'OK'),
    ('setup: remember the id of the second code', null, null, null, $s$select set_config('verify.code2_id', (select id from public.join_codes where label = 'verify2')::text, true)$s$, 'OK'),
    ('suspend: suspended user cannot re-enter with a valid code', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select public.redeem_join_code(current_setting('verify.code2'), 'Member')->>'status'$s$, 'VALUE:blocked'),
    ('reinstate: admin cannot reinstate themselves', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.reinstate_member(current_setting('verify.mem_a')::uuid)$s$, '42501'),
    ('reinstate: admin with MFA reinstates', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.reinstate_member(current_setting('verify.mem_m')::uuid)->>'status'$s$, 'VALUE:approved'),
    ('reinstate: access is back', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:1'),
    ('grant: plain member cannot grant themselves Team Lead', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_m')::uuid, 'team_lead')$s$, '42501'),
    ('grant: admin cannot grant themselves anything', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_a')::uuid, 'team_lead')$s$, '42501'),
    ('grant: admin cannot grant Admin (Superadmin only, Phase 1e)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_m')::uuid, 'admin')$s$, '42501'),
    ('grant: admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.grant_app_role(current_setting('verify.mem_m')::uuid, 'team_lead')$s$, '42501'),
    ('grant: admin with MFA grants Team Lead', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_m')::uuid, 'team_lead')->>'status'$s$, 'VALUE:granted'),
    ('grant: member now holds member and team_lead', null, null, null, $s$select string_agg(a.key, ',' order by a.key) from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id join public.team_memberships m on m.id = r.membership_id where m.user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$s$, 'VALUE:member,team_lead'),
    ('grant: Team Lead does not gain admin powers (cannot create codes)', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('grant: target must be an approved member', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_n3')::uuid, 'team_lead')->>'status'$s$, 'VALUE:not_approved'),
    ('revoke role: admin with MFA revokes Team Lead', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.revoke_app_role(current_setting('verify.mem_m')::uuid, 'team_lead')->>'status'$s$, 'VALUE:revoked'),
    ('revoke role: Admin role cannot be revoked here', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.revoke_app_role(current_setting('verify.mem_a2')::uuid, 'admin')$s$, '42501'),
    ('revoke code: plain member refused', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.revoke_join_code(current_setting('verify.code2_id')::uuid)$s$, '42501'),
    ('revoke code: admin with MFA revokes', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.revoke_join_code(current_setting('verify.code2_id')::uuid)->>'status'$s$, 'VALUE:revoked'),
    ('revoke code: a revoked code no longer works', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.redeem_join_code(current_setting('verify.code2'), 'Stranger')->>'status'$s$, 'VALUE:invalid_code'),
    ('bootstrap: unconfirmed user refused', null, null, null, $s$select private.bootstrap_superadmin('dddddddd-dddd-4ddd-8ddd-dddddddddddd', current_setting('verify.team_a')::uuid, 'X')$s$, '22023'),
    ('bootstrap: unknown user refused', null, null, null, $s$select private.bootstrap_superadmin(gen_random_uuid(), current_setting('verify.team_a')::uuid, 'X')$s$, '22023'),
    ('bootstrap: blank display name refused', null, null, null, $s$select private.bootstrap_superadmin('66666666-6666-4666-8666-666666666666', current_setting('verify.team_a')::uuid, '  ')$s$, '22023'),
    ('bootstrap: unknown team refused', null, null, null, $s$select private.bootstrap_superadmin('66666666-6666-4666-8666-666666666666', gen_random_uuid(), 'X')$s$, '22023'),
    ('bootstrap: first Superadmin created', null, null, null, $s$select private.bootstrap_superadmin('66666666-6666-4666-8666-666666666666', current_setting('verify.team_a')::uuid, 'Owner Person')->>'status'$s$, 'VALUE:bootstrapped'),
    ('bootstrap: the owner row is active', null, null, null, $s$select count(*)::text from public.platform_owners where user_id = '66666666-6666-4666-8666-666666666666' and revoked_at is null$s$, 'VALUE:1'),
    ('bootstrap: created an approved membership with the Member bundle only', null, null, null, $s$select m.membership_status || ':' || (select string_agg(a.key, ',' order by a.key) from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id where r.membership_id = m.id) from public.team_memberships m where m.user_id = '66666666-6666-4666-8666-666666666666'$s$, 'VALUE:approved:member'),
    ('bootstrap: audited with no acting user', null, null, null, $s$select count(*)::text from public.audit_logs where action = 'superadmin.bootstrapped' and actor_user_id is null$s$, 'VALUE:1'),
    ('bootstrap: a second run is refused without recovery mode', null, null, null, $s$select private.bootstrap_superadmin('77777777-7777-4777-8777-777777777777', current_setting('verify.team_a')::uuid, 'Second')$s$, '42501'),
    ('bootstrap: recovery mode adds another Superadmin', null, null, null, $s$select private.bootstrap_superadmin('77777777-7777-4777-8777-777777777777', current_setting('verify.team_a')::uuid, 'Second Owner', true)->>'status'$s$, 'VALUE:recovered'),
    ('bootstrap: two active owners now', null, null, null, $s$select count(*)::text from public.platform_owners where revoked_at is null$s$, 'VALUE:2'),
    ('last owner: revoking one of two is allowed', null, null, null, $s$update public.platform_owners set revoked_at = now() where user_id = '77777777-7777-4777-8777-777777777777'$s$, 'OK'),
    ('last owner: revoking the last active Superadmin is blocked', null, null, null, $s$update public.platform_owners set revoked_at = now() where user_id = '66666666-6666-4666-8666-666666666666'$s$, '42501'),
    ('last owner: deleting the last active Superadmin is blocked', null, null, null, $s$delete from public.platform_owners where user_id = '66666666-6666-4666-8666-666666666666'$s$, '42501'),
    ('last owner: identity columns are immutable', null, null, null, $s$update public.platform_owners set user_id = gen_random_uuid() where user_id = '66666666-6666-4666-8666-666666666666'$s$, '42501'),
    ('recovery: a revoked Superadmin can be restored through the runbook path', null, null, null, $s$select private.bootstrap_superadmin('77777777-7777-4777-8777-777777777777', current_setting('verify.team_a')::uuid, 'Second Owner', true)->>'status'$s$, 'VALUE:recovered'),
    ('anon cannot read platform_owners', 'anon', null, null, $s$select * from public.platform_owners$s$, '42501'),
    ('Superadmin cannot read platform_owners through the API', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select * from public.platform_owners$s$, '42501'),
    ('Superadmin cannot write platform_owners through the API', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$insert into public.platform_owners (user_id) values ('12121212-1212-4212-8212-121212121212')$s$, '42501'),
    ('member cannot make themselves Superadmin', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$insert into public.platform_owners (user_id) values ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$s$, '42501'),
    ('member cannot call get_my_access as anon would', 'anon', null, null, $s$select public.get_my_access(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('setup: remember mem_n', null, null, null, $s$select set_config('verify.mem_n', (select id from public.team_memberships where user_id = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')::text, true)$s$, 'OK'),
    ('setup: remember mem_su', null, null, null, $s$select set_config('verify.mem_su', (select id from public.team_memberships where user_id = '66666666-6666-4666-8666-666666666666')::text, true)$s$, 'OK'),
    ('setup: remember req_n3b', null, null, null, $s$select set_config('verify.req_n3b', (select id from public.join_requests where user_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff' and status = 'pending')::text, true)$s$, 'OK'),
    ('setup: remember cnt_mem_a', null, null, null, $s$select set_config('verify.cnt_mem_a', (select count(*) from public.team_memberships where team_id = current_setting('verify.team_a')::uuid)::text, true)$s$, 'OK'),
    ('setup: remember cnt_mem_b', null, null, null, $s$select set_config('verify.cnt_mem_b', (select count(*) from public.team_memberships where team_id = current_setting('verify.team_b')::uuid)::text, true)$s$, 'OK'),
    ('setup: remember cnt_mem_all', null, null, null, $s$select set_config('verify.cnt_mem_all', (select count(*) from public.team_memberships)::text, true)$s$, 'OK'),
    ('setup: remember cnt_req_a', null, null, null, $s$select set_config('verify.cnt_req_a', (select count(*) from public.join_requests where team_id = current_setting('verify.team_a')::uuid)::text, true)$s$, 'OK'),
    ('setup: remember cnt_req_b', null, null, null, $s$select set_config('verify.cnt_req_b', (select count(*) from public.join_requests where team_id = current_setting('verify.team_b')::uuid)::text, true)$s$, 'OK'),
    ('setup: remember cnt_req_all', null, null, null, $s$select set_config('verify.cnt_req_all', (select count(*) from public.join_requests)::text, true)$s$, 'OK'),
    ('setup: remember cnt_codes_a', null, null, null, $s$select set_config('verify.cnt_codes_a', (select count(*) from public.join_codes where team_id = current_setting('verify.team_a')::uuid)::text, true)$s$, 'OK'),
    ('setup: remember cnt_codes_all', null, null, null, $s$select set_config('verify.cnt_codes_all', (select count(*) from public.join_codes)::text, true)$s$, 'OK'),
    ('setup: remember cnt_prof_a', null, null, null, $s$select set_config('verify.cnt_prof_a', (select count(*) from public.profiles p where exists (select 1 from public.team_memberships m where m.user_id = p.user_id and m.team_id = current_setting('verify.team_a')::uuid))::text, true)$s$, 'OK'),
    ('setup: remember cnt_prof_b', null, null, null, $s$select set_config('verify.cnt_prof_b', (select count(*) from public.profiles p where exists (select 1 from public.team_memberships m where m.user_id = p.user_id and m.team_id = current_setting('verify.team_b')::uuid))::text, true)$s$, 'OK'),
    ('setup: remember cnt_prof_any', null, null, null, $s$select set_config('verify.cnt_prof_any', (select count(*) from public.profiles p where exists (select 1 from public.team_memberships m where m.user_id = p.user_id))::text, true)$s$, 'OK'),
    ('persona Admin: memberships visible = rows of their own scope only', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_mem_a'))::text from public.team_memberships$s$, 'VALUE:true'),
    ('persona Admin: join requests visible = rows of their own scope only', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_req_a'))::text from public.join_requests$s$, 'VALUE:true'),
    ('persona Admin: profiles visible = rows of their own scope only', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_prof_a'))::text from public.profiles$s$, 'VALUE:true'),
    ('persona Admin: join code metadata visible = rows of their own scope only', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_codes_a'))::text from public.join_codes$s$, 'VALUE:true'),
    ('persona Admin: no membership row of the other team', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select count(*)::text from public.team_memberships where team_id = current_setting('verify.team_b')::uuid$s$, 'VALUE:0'),
    ('persona Admin: cannot read code hashes', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select code_hash from public.join_codes$s$, '42501'),
    ('persona Other-team Admin: memberships visible = rows of their own scope only', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_mem_b'))::text from public.team_memberships$s$, 'VALUE:true'),
    ('persona Other-team Admin: join requests visible = rows of their own scope only', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_req_b'))::text from public.join_requests$s$, 'VALUE:true'),
    ('persona Other-team Admin: profiles visible = rows of their own scope only', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_prof_b'))::text from public.profiles$s$, 'VALUE:true'),
    ('persona Other-team Admin: join code metadata', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Other-team Admin: no membership row of the other team', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select count(*)::text from public.team_memberships where team_id = current_setting('verify.team_a')::uuid$s$, 'VALUE:0'),
    ('persona Other-team Admin: cannot read code hashes', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal1', $s$select code_hash from public.join_codes$s$, '42501'),
    ('persona Superadmin: memberships visible = rows of their own scope only', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_mem_all'))::text from public.team_memberships$s$, 'VALUE:true'),
    ('persona Superadmin: join requests visible = rows of their own scope only', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_req_all'))::text from public.join_requests$s$, 'VALUE:true'),
    ('persona Superadmin: profiles visible = rows of their own scope only', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_prof_any'))::text from public.profiles$s$, 'VALUE:true'),
    ('persona Superadmin: join code metadata visible = rows of their own scope only', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (count(*)::text = current_setting('verify.cnt_codes_all'))::text from public.join_codes$s$, 'VALUE:true'),
    ('persona Superadmin: sees memberships of both teams', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (count(distinct team_id) >= 2)::text from public.team_memberships$s$, 'VALUE:true'),
    ('persona Superadmin: cannot read code hashes', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select code_hash from public.join_codes$s$, '42501'),
    ('persona Superadmin: reads the team through membership', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select count(id)::text from public.teams$s$, 'VALUE:1'),
    ('persona Member: no other memberships', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(*)::text from public.team_memberships where user_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$s$, 'VALUE:0'),
    ('persona Member: sees only their own join requests (0)', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(*)::text from public.join_requests$s$, 'VALUE:0'),
    ('persona Member: no other profiles', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(*)::text from public.profiles where user_id <> 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'$s$, 'VALUE:0'),
    ('persona Member: no join code metadata', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Member: cannot create a joining code even with MFA', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Team Lead: no other memberships', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal1', $s$select count(*)::text from public.team_memberships where user_id <> '88888888-8888-4888-8888-888888888888'$s$, 'VALUE:0'),
    ('persona Team Lead: sees only their own join requests (0)', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal1', $s$select count(*)::text from public.join_requests$s$, 'VALUE:0'),
    ('persona Team Lead: no other profiles', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal1', $s$select count(*)::text from public.profiles where user_id <> '88888888-8888-4888-8888-888888888888'$s$, 'VALUE:0'),
    ('persona Team Lead: no join code metadata', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Team Lead: cannot create a joining code even with MFA', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Suspended member: no other memberships', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select count(*)::text from public.team_memberships where user_id <> '99999999-9999-4999-8999-999999999999'$s$, 'VALUE:0'),
    ('persona Suspended member: sees only their own join requests (0)', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select count(*)::text from public.join_requests$s$, 'VALUE:0'),
    ('persona Suspended member: no other profiles', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select count(*)::text from public.profiles where user_id <> '99999999-9999-4999-8999-999999999999'$s$, 'VALUE:0'),
    ('persona Suspended member: no join code metadata', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Suspended member: cannot create a joining code even with MFA', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Stranger: no other memberships', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select count(*)::text from public.team_memberships where user_id <> '12121212-1212-4212-8212-121212121212'$s$, 'VALUE:0'),
    ('persona Stranger: sees only their own join requests (0)', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select count(*)::text from public.join_requests$s$, 'VALUE:0'),
    ('persona Stranger: no other profiles', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select count(*)::text from public.profiles where user_id <> '12121212-1212-4212-8212-121212121212'$s$, 'VALUE:0'),
    ('persona Stranger: no join code metadata', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Stranger: cannot create a joining code even with MFA', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Approved newcomer: no other memberships', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(*)::text from public.team_memberships where user_id <> 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:0'),
    ('persona Approved newcomer: sees only their own join requests (1)', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(*)::text from public.join_requests$s$, 'VALUE:1'),
    ('persona Approved newcomer: no other profiles', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(*)::text from public.profiles where user_id <> 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'$s$, 'VALUE:0'),
    ('persona Approved newcomer: no join code metadata', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal1', $s$select count(*)::text from public.join_codes$s$, 'VALUE:0'),
    ('persona Approved newcomer: cannot create a joining code even with MFA', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Other-team Admin: cannot create a code for this team even with MFA', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'x')$s$, '42501'),
    ('persona Team Lead: cannot approve requests even with MFA', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n3b')::uuid, 'approve')$s$, '42501'),
    ('persona Suspended member: sees own row only, no team', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select count(id)::text || '/' || (select count(id)::text from public.teams) from public.team_memberships$s$, 'VALUE:1/0'),
    ('get_my_access: Admin', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (public.get_my_access(current_setting('verify.team_a')::uuid)->>'superadmin') || ':' || jsonb_array_length(public.get_my_access(current_setting('verify.team_a')::uuid)->'permissions')$s$, 'VALUE:false:5'),
    ('get_my_access: Superadmin', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select (public.get_my_access(current_setting('verify.team_a')::uuid)->>'superadmin') || ':' || jsonb_array_length(public.get_my_access(current_setting('verify.team_a')::uuid)->'permissions')$s$, 'VALUE:true:5'),
    ('get_my_access: plain member has no permissions', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal1', $s$select jsonb_array_length(public.get_my_access(current_setting('verify.team_a')::uuid)->'permissions')::text$s$, 'VALUE:0'),
    ('get_my_access: suspended member has no permissions', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select jsonb_array_length(public.get_my_access(current_setting('verify.team_a')::uuid)->'permissions')::text$s$, 'VALUE:0'),
    ('Superadmin without MFA is refused', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal1', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'su')$s$, '42501'),
    ('Superadmin with MFA creates a code without holding any Admin role', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select set_config('verify.code3', public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'su')->>'code', true)$s$, 'OK'),
    ('Superadmin with MFA approves a request', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.review_join_request(current_setting('verify.req_n3b')::uuid, 'approve')->>'status'$s$, 'VALUE:approved'),
    ('Superadmin cannot grant themselves Admin', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_su')::uuid, 'admin')$s$, '42501'),
    ('Superadmin cannot suspend themselves', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_su')::uuid)$s$, '42501'),
    ('Superadmin grants Admin to an approved member', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_m')::uuid, 'admin')->>'status'$s$, 'VALUE:granted'),
    ('new Admin can create a code with MFA', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'new-admin')->>'expires_at' is not null$s$, 'VALUE:true'),
    ('new Admin still cannot grant Admin to others', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.grant_app_role(current_setting('verify.mem_n')::uuid, 'admin')$s$, '42501'),
    ('Admin cannot suspend the Superadmin', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_su')::uuid)$s$, '42501'),
    ('Superadmin suspends an Admin', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.suspend_member(current_setting('verify.mem_m')::uuid, 'verify')->>'status'$s$, 'VALUE:suspended'),
    ('Superadmin reinstates the Admin', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.reinstate_member(current_setting('verify.mem_m')::uuid)->>'status'$s$, 'VALUE:approved'),
    ('Superadmin revokes the Admin role', 'authenticated', '66666666-6666-4666-8666-666666666666', 'aal2', $s$select public.revoke_app_role(current_setting('verify.mem_m')::uuid, 'admin')->>'status'$s$, 'VALUE:revoked'),
    ('former Admin can no longer create codes', 'authenticated', 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'aal2', $s$select public.create_join_code(current_setting('verify.team_a')::uuid, 1, 1, 'gone')$s$, '42501'),
    ('Admin role bundle removal left the Member role intact', null, null, null, $s$select string_agg(a.key, ',' order by a.key) from public.member_app_roles r join public.app_roles a on a.id = r.app_role_id where r.membership_id = current_setting('verify.mem_m')::uuid$s$, 'VALUE:member'),
    ('direct client write/read blocked: insert into team_memberships', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$insert into public.team_memberships (team_id, user_id, membership_status) values (current_setting('verify.team_a')::uuid, '12121212-1212-4212-8212-121212121212', 'approved')$s$, '42501'),
    ('direct client write/read blocked: self-approve by updating team_memberships', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$update public.team_memberships set membership_status = 'approved' where user_id = 'ffffffff-ffff-4fff-8fff-ffffffffffff'$s$, '42501'),
    ('direct client write/read blocked: insert into join_requests', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$insert into public.join_requests (team_id, user_id, status) values (current_setting('verify.team_a')::uuid, '12121212-1212-4212-8212-121212121212', 'approved')$s$, '42501'),
    ('direct client write/read blocked: insert into member_app_roles', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$insert into public.member_app_roles (membership_id, app_role_id) select m.id, a.id from public.team_memberships m, public.app_roles a where m.user_id = '12121212-1212-4212-8212-121212121212' and a.key = 'admin'$s$, '42501'),
    ('direct client write/read blocked: read join_codes', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select code_hash from public.join_codes$s$, '42501'),
    ('direct client write/read blocked: read app_roles', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select * from public.app_roles$s$, '42501'),
    ('direct client write/read blocked: read member_app_roles', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select * from public.member_app_roles$s$, '42501'),
    ('direct client write/read blocked: read rate_limit_events', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select * from public.rate_limit_events$s$, '42501'),
    ('direct client write/read blocked: insert into rate_limit_events', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$insert into public.rate_limit_events (user_id, action) values (null, 'x')$s$, '42501'),
    ('direct client write/read blocked: insert into join_codes', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$insert into public.join_codes (team_id, code_hash, expires_at, max_uses) values (current_setting('verify.team_a')::uuid, 'x', now() + interval '1 day', 1)$s$, '42501'),
    ('direct client call of the bootstrap function is refused', 'authenticated', 'cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'aal2', $s$select private.bootstrap_superadmin(gen_random_uuid(), current_setting('verify.team_a')::uuid, 'x')$s$, '42501'),
    ('audit: every privileged action left a record', null, null, null, $s$select count(distinct action)::text from public.audit_logs where action in ('join_code.created','join_code.redeemed','join_code.revoked','membership.approved','membership.rejected','membership.suspended','membership.reinstated','app_role.granted','app_role.revoked','superadmin.bootstrapped','superadmin.recovered')$s$, 'VALUE:11'),
    ('audit: no raw joining code appears in any audit record', null, null, null, $s$select count(*)::text from public.audit_logs where metadata::text ilike '%' || replace(current_setting('verify.code'), '-', '') || '%' or metadata::text ilike '%' || current_setting('verify.code') || '%' or metadata::text ilike '%' || current_setting('verify.code2') || '%'$s$, 'VALUE:0'),
    ('audit: records name the acting administrator', null, null, null, $s$select count(*)::text from public.audit_logs where action = 'membership.approved' and actor_user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$s$, 'VALUE:1'),
    ('audit: nothing recorded for the rejected attempts by non-admins', null, null, null, $s$select count(*)::text from public.audit_logs where actor_user_id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb' and action like 'membership.%'$s$, 'VALUE:0'),
    ('setup: remember role ids (BAU, Queue Manager, Retain, Reconciliation, other-team Queue Manager)', null, null, null, $s$select set_config('verify.role_bau', (select id::text from public.operational_roles where team_id = current_setting('verify.team_a')::uuid and name = 'BAU / Ticketing'), true), set_config('verify.role_queue', (select id::text from public.operational_roles where team_id = current_setting('verify.team_a')::uuid and name = 'Queue Manager'), true), set_config('verify.role_retain', (select id::text from public.operational_roles where team_id = current_setting('verify.team_a')::uuid and name = 'Retain'), true), set_config('verify.role_recon', (select id::text from public.operational_roles where team_id = current_setting('verify.team_a')::uuid and name = 'Reconciliation'), true), set_config('verify.role_other', (select id::text from public.operational_roles where team_id = current_setting('verify.team_b')::uuid and name = 'Queue Manager'), true)$s$, 'OK'),
    ('the six initial roles exist for the team', null, null, null, $s$select string_agg(name, ',' order by name collate "C") from public.operational_roles where team_id = current_setting('verify.team_a')::uuid$s$, 'VALUE:BAU / Ticketing,Onboarding,Queue Manager,Reconciliation,Resignation,Retain'),
    ('direct client access blocked: read operational_roles', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select * from public.operational_roles$s$, '42501'),
    ('direct client access blocked: insert into operational_roles', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$insert into public.operational_roles (team_id, name) values (current_setting('verify.team_a')::uuid, 'Sneaky')$s$, '42501'),
    ('direct client access blocked: update operational_roles', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$update public.operational_roles set name = 'x'$s$, '42501'),
    ('direct client access blocked: read member_operational_roles', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select * from public.member_operational_roles$s$, '42501'),
    ('direct client access blocked: insert into member_operational_roles', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$insert into public.member_operational_roles (membership_id, operational_role_id) values (gen_random_uuid(), gen_random_uuid())$s$, '42501'),
    ('create role: anon refused', 'anon', null, null, $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Custom Role', null)$s$, '42501'),
    ('create role: Admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Custom Role', null)$s$, '42501'),
    ('create role: Team Lead refused', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Custom Role', null)$s$, '42501'),
    ('create role: plain member refused', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Custom Role', null)$s$, '42501'),
    ('create role: another team''s Admin refused', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Custom Role', null)$s$, '42501'),
    ('create role: blank name refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, '   ')$s$, '22023'),
    ('create role: 61-character name refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, repeat('x', 61))$s$, '22023'),
    ('create role: 201-character description refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Too Wordy', repeat('x', 201))$s$, '22023'),
    ('create role: unknown team refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_operational_role(gen_random_uuid(), 'Ghost')$s$, '42501'),
    ('create role: Admin with MFA creates a new role without any code change (AC-M5)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select set_config('verify.role_custom', public.create_operational_role(current_setting('verify.team_a')::uuid, '  Custom Role  ', 'added by an Admin')->>'id', true)$s$, 'OK'),
    ('create role: name is trimmed and stored', null, null, null, $s$select name from public.operational_roles where id = current_setting('verify.role_custom')::uuid$s$, 'VALUE:Custom Role'),
    ('create role: a duplicate name (any case) is reported, not an error', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'custom ROLE')->>'status'$s$, 'VALUE:duplicate'),
    ('update role: Team Lead refused', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, 'Hijacked')$s$, '42501'),
    ('update role: Admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, 'Hijacked')$s$, '42501'),
    ('update role: another team''s Admin refused', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, 'Hijacked')$s$, '42501'),
    ('update role: unknown id and no permission look the same', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.update_operational_role(gen_random_uuid(), 'x')$s$, '42501'),
    ('update role: renaming to an existing name (any case) is reported', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, 'retain')->>'status'$s$, 'VALUE:duplicate'),
    ('update role: Admin with MFA renames and re-describes', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, 'Escalations', 'second line')->>'status'$s$, 'VALUE:updated'),
    ('update role: rename is recorded in history (id unchanged, new name stored)', null, null, null, $s$select name || '|' || description from public.operational_roles where id = current_setting('verify.role_custom')::uuid$s$, 'VALUE:Escalations|second line'),
    ('update role: an empty description clears it', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, null, '')->>'status'$s$, 'VALUE:updated'),
    ('update role: invalid name refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_custom')::uuid, repeat('x', 61))$s$, '22023'),
    ('assign: Team Lead refused', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_queue')::uuid)$s$, '42501'),
    ('assign: Admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_queue')::uuid)$s$, '42501'),
    ('assign: another team''s Admin refused', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_queue')::uuid)$s$, '42501'),
    ('assign: a member cannot assign themselves a role', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_queue')::uuid)$s$, '42501'),
    ('assign: a role from another team is refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_other')::uuid)$s$, '22023'),
    ('assign: a pending member cannot be assigned', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_pp')::uuid, current_setting('verify.role_queue')::uuid, false)->>'status'$s$, 'VALUE:not_approved'),
    ('assign: a suspended member cannot be assigned', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_sus2')::uuid, current_setting('verify.role_queue')::uuid, false)->>'status'$s$, 'VALUE:not_approved'),
    ('assign: Queue Manager to a member as primary', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_queue')::uuid, true)->>'status'$s$, 'VALUE:assigned'),
    ('assign: the same member also holds Retain (several roles per member, AC-M4)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_retain')::uuid, false)->>'status'$s$, 'VALUE:assigned'),
    ('assign: the member now holds both', null, null, null, $s$select string_agg(r.name, ',' order by r.name) from public.member_operational_roles x join public.operational_roles r on r.id = x.operational_role_id where x.membership_id = current_setting('verify.mem_r1')::uuid$s$, 'VALUE:Queue Manager,Retain'),
    ('assign: the new custom role can be assigned too', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_custom')::uuid, false)->>'status'$s$, 'VALUE:assigned'),
    ('assign: making Retain primary clears the previous primary', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_retain')::uuid, true)->>'status'$s$, 'VALUE:assigned'),
    ('assign: exactly one primary remains', null, null, null, $s$select string_agg(r.name, ',') from public.member_operational_roles x join public.operational_roles r on r.id = x.operational_role_id where x.membership_id = current_setting('verify.mem_r1')::uuid and x.is_primary$s$, 'VALUE:Retain'),
    ('assign: roles are separate from application permissions (member bundle unchanged)', null, null, null, $s$select string_agg(a.key, ',') from public.member_app_roles mr join public.app_roles a on a.id = mr.app_role_id where mr.membership_id = current_setting('verify.mem_r1')::uuid$s$, 'VALUE:member'),
    ('assign: holding Queue Manager gives no admin power', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal2', $s$select public.create_operational_role(current_setting('verify.team_a')::uuid, 'Power Grab')$s$, '42501'),
    ('assign: Admin assigns BAU to a second member', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r2')::uuid, current_setting('verify.role_bau')::uuid, false)->>'status'$s$, 'VALUE:assigned'),
    ('deactivate: Admin deactivates BAU', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_bau')::uuid, null, null, false)->>'status'$s$, 'VALUE:updated'),
    ('deactivate: existing assignment is kept as history', null, null, null, $s$select count(*)::text from public.member_operational_roles where operational_role_id = current_setting('verify.role_bau')::uuid$s$, 'VALUE:1'),
    ('deactivate: an inactive role cannot be newly assigned', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.assign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_bau')::uuid, false)->>'status'$s$, 'VALUE:role_inactive'),
    ('deactivate: Admin deactivates Reconciliation too', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.update_operational_role(current_setting('verify.role_recon')::uuid, null, null, false)->>'status'$s$, 'VALUE:updated'),
    ('delete: a role that has been assigned cannot be deleted', null, null, null, $s$delete from public.operational_roles where id = current_setting('verify.role_retain')::uuid$s$, '23503'),
    ('unassign: Team Lead refused', 'authenticated', '88888888-8888-4888-8888-888888888888', 'aal2', $s$select public.unassign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_custom')::uuid)$s$, '42501'),
    ('unassign: Admin without MFA refused', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select public.unassign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_custom')::uuid)$s$, '42501'),
    ('unassign: Admin with MFA removes the custom role', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.unassign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_custom')::uuid)->>'status'$s$, 'VALUE:unassigned'),
    ('unassign: removing it again is a harmless no-op', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal2', $s$select public.unassign_operational_role(current_setting('verify.mem_r1')::uuid, current_setting('verify.role_custom')::uuid)->>'status'$s$, 'VALUE:not_assigned'),
    ('list roles: anon refused', 'anon', null, null, $s$select public.list_operational_roles(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('list roles: a non-member is refused', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.list_operational_roles(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('list roles: a pending member is refused', 'authenticated', 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', 'aal1', $s$select public.list_operational_roles(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('list roles: a suspended member is refused', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select public.list_operational_roles(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('list roles: another team''s member is refused', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.list_operational_roles(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('list roles: an ordinary member sees only active roles (5 of 7)', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal1', $s$select jsonb_array_length(public.list_operational_roles(current_setting('verify.team_a')::uuid))::text$s$, 'VALUE:5'),
    ('list roles: an Admin also sees the inactive roles (7)', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select jsonb_array_length(public.list_operational_roles(current_setting('verify.team_a')::uuid))::text$s$, 'VALUE:7'),
    ('list roles: member counts are reported', 'authenticated', 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'aal1', $s$select (public.list_operational_roles(current_setting('verify.team_a')::uuid)::text like '%"member_count": 1%')::text$s$, 'VALUE:true'),
    ('directory: anon refused', 'anon', null, null, $s$select public.team_directory(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('directory: a non-member is refused', 'authenticated', '12121212-1212-4212-8212-121212121212', 'aal1', $s$select public.team_directory(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('directory: a pending member is refused', 'authenticated', 'd1d1d1d1-d1d1-4d1d-8d1d-d1d1d1d1d1d1', 'aal1', $s$select public.team_directory(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('directory: a suspended member is refused', 'authenticated', '99999999-9999-4999-8999-999999999999', 'aal1', $s$select public.team_directory(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('directory: another team''s Admin is refused', 'authenticated', '44444444-4444-4444-8444-444444444444', 'aal2', $s$select public.team_directory(current_setting('verify.team_a')::uuid)$s$, '42501'),
    ('setup: remember how many approved members the team has', null, null, null, $s$select set_config('verify.approved_count', (select count(*)::text from public.team_memberships where team_id = current_setting('verify.team_a')::uuid and membership_status = 'approved'), true)$s$, 'OK'),
    ('directory: an ordinary member sees exactly the approved members', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal1', $s$select (jsonb_array_length(public.team_directory(current_setting('verify.team_a')::uuid)) = current_setting('verify.approved_count')::int)::text$s$, 'VALUE:true'),
    ('directory: shows names, titles and active roles', 'authenticated', 'c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2', 'aal1', $s$select ((public.team_directory(current_setting('verify.team_a')::uuid)::text like '%Role One%') and (public.team_directory(current_setting('verify.team_a')::uuid)::text like '%UAM Engineer%') and (public.team_directory(current_setting('verify.team_a')::uuid)::text like '%Retain%'))::text$s$, 'VALUE:true'),
    ('directory: pending and suspended people never appear', 'authenticated', 'c2c2c2c2-c2c2-4c2c-8c2c-c2c2c2c2c2c2', 'aal1', $s$select (public.team_directory(current_setting('verify.team_a')::uuid)::text like '%Pending Person%')::text$s$, 'VALUE:false'),
    ('directory: deactivated roles are hidden from member chips', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal1', $s$select (public.team_directory(current_setting('verify.team_a')::uuid)::text like '%BAU%')::text$s$, 'VALUE:false'),
    ('directory: no e-mail address and no user id', 'authenticated', 'c1c1c1c1-c1c1-4c1c-8c1c-c1c1c1c1c1c1', 'aal1', $s$select (public.team_directory(current_setting('verify.team_a')::uuid)::text ~* '(example.invalid|user_id)')::text$s$, 'VALUE:false'),
    ('audit: role changes are recorded (created, updated, assigned, unassigned)', null, null, null, $s$select count(distinct action)::text from public.audit_logs where action in ('operational_role.created','operational_role.updated','operational_role.assigned','operational_role.unassigned')$s$, 'VALUE:4'),
    ('audit: role records name the acting Admin', null, null, null, $s$select count(*)::text from public.audit_logs where action = 'operational_role.created' and actor_user_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'$s$, 'VALUE:1')
  ) as t(name, role, sub, aal, sql, expect) loop
    begin
      if c.role is not null then
        execute format('set local role %I', c.role);
        if c.sub is not null then
          perform set_config('request.jwt.claims',
            json_build_object('sub', c.sub, 'role', c.role, 'aal', coalesce(c.aal, 'aal1'))::text, true);
          perform set_config('request.jwt.claim.sub', c.sub, true);
        end if;
      end if;
      if c.expect like 'VALUE:%' then
        execute c.sql into got;
        ok := (got = substr(c.expect, 7));
        got := 'VALUE:' || coalesce(got, 'null');
      else
        execute c.sql;
        got := 'OK';
        ok := (c.expect = 'OK');
      end if;
    exception when others then
      got := sqlstate;
      ok := (got = c.expect);
    end;
    reset role;
    if ok then n_pass := n_pass + 1; report := report || E'PASS  ' || c.name || E'\n';
    else n_fail := n_fail + 1;
      report := report || E'FAIL  ' || c.name || ' (expected ' || c.expect || ', got ' || got || E')\n';
    end if;
  end loop;

  raise exception E'VERIFY RESULT: % (% passed, % failed)\n%',
    case when n_fail = 0 then 'PASS' else 'FAIL' end, n_pass, n_fail, report
    using errcode = 'P0001';
end
$verify$;
