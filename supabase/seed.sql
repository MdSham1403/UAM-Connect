-- Development seed: ONE clearly synthetic team. Deterministic and idempotent.
-- Runs only on local `supabase db reset`; it is never applied to a hosted project
-- by `supabase db push`. Contains no real team, employer, banking or customer data.
insert into public.teams (id, name, timezone)
values (
  '00000000-0000-4000-8000-000000000001',
  'Synthetic Dev Team (not real data)',
  'UTC'
)
on conflict (id) do nothing;
