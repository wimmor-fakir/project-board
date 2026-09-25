-- Run this once in your Supabase project's SQL Editor, AFTER
-- supabase-burn-forecast.sql (it reuses that file's burn_forecast_allowed()).
--
-- Adds named, date-stamped scenarios to the Burn Forecasting page. A
-- scenario is a snapshot of BOTH:
--   * expenses -- the whole Burn Forecasting sheet (burn_forecast 'main'), and
--   * income   -- every Forecasting page line and its monthly locations/price
--                 (forecast_lines + project_forecasts).
-- Reinstating a scenario puts both back exactly as they were saved. Before
-- it does, it automatically saves the current state as another scenario
-- ("Auto-saved before reinstating ..."), so a reinstate can always be undone.
--
-- Scenarios hold the same company financials as the Burn Forecasting page,
-- so the same rule applies: only the admin and people ticked for "Burn
-- Forecasting" can list, save, download, reinstate or delete them.
-- Saving and reinstating run as database functions so each happens as one
-- all-or-nothing step (a reinstate can't stop half-way), and so reinstated
-- Forecasting lines keep their original ids.

create table if not exists burn_scenarios (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by text,
  created_at timestamptz not null default now(),
  expenses jsonb,
  income jsonb not null
);

alter table burn_scenarios enable row level security;

drop policy if exists "Burn Forecasting access can read scenarios" on burn_scenarios;
create policy "Burn Forecasting access can read scenarios"
  on burn_scenarios for select
  using (burn_forecast_allowed());

drop policy if exists "Burn Forecasting access can delete scenarios" on burn_scenarios;
create policy "Burn Forecasting access can delete scenarios"
  on burn_scenarios for delete
  using (burn_forecast_allowed());

-- Snapshot the current expenses + income under p_name. Returns the new id.
create or replace function save_burn_scenario(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  if not burn_forecast_allowed() then
    raise exception 'Not authorized for Burn Forecasting';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'A scenario needs a name';
  end if;
  insert into burn_scenarios (name, created_by, expenses, income)
  values (
    trim(p_name),
    auth.jwt() ->> 'email',
    (select payload from burn_forecast where id = 'main'),
    jsonb_build_object(
      'lines', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', l.id, 'project_id', l.project_id, 'label', l.label,
          'sort_order', l.sort_order, 'included_in_chart', l.included_in_chart
        ) order by l.id)
        from forecast_lines l), '[]'::jsonb),
      'forecasts', coalesce((
        select jsonb_agg(jsonb_build_object(
          'line_id', f.line_id, 'month', f.month, 'locations', f.locations, 'price', f.price
        ) order by f.line_id, f.month)
        from project_forecasts f), '[]'::jsonb)
    )
  )
  returning id into new_id;
  return new_id;
end $$;

-- Put a saved scenario's expenses and income back, after auto-saving the
-- current state.
create or replace function reinstate_burn_scenario(p_scenario_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  s burn_scenarios%rowtype;
begin
  if not burn_forecast_allowed() then
    raise exception 'Not authorized for Burn Forecasting';
  end if;
  select * into s from burn_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'Scenario not found';
  end if;

  perform save_burn_scenario('Auto-saved before reinstating "' || s.name || '"');

  if s.expenses is not null then
    insert into burn_forecast (id, payload, updated_by, updated_at)
    values ('main', s.expenses, coalesce(auth.jwt() ->> 'email', '') || ' (reinstated "' || s.name || '")', now())
    on conflict (id) do update
      set payload = excluded.payload, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;

  delete from project_forecasts where true; -- "where true": Supabase rejects a bare DELETE
  delete from forecast_lines
  where id not in (select (l ->> 'id')::bigint from jsonb_array_elements(s.income -> 'lines') l);

  insert into forecast_lines (id, project_id, label, sort_order, included_in_chart)
  overriding system value
  select (l ->> 'id')::bigint, l ->> 'project_id', l ->> 'label',
         coalesce((l ->> 'sort_order')::int, 0), coalesce((l ->> 'included_in_chart')::boolean, true)
  from jsonb_array_elements(s.income -> 'lines') l
  on conflict (id) do update
    set project_id = excluded.project_id, label = excluded.label,
        sort_order = excluded.sort_order, included_in_chart = excluded.included_in_chart;

  insert into project_forecasts (line_id, month, locations, price, updated_by, updated_at)
  select (f ->> 'line_id')::bigint, (f ->> 'month')::date,
         coalesce((f ->> 'locations')::int, 0), coalesce((f ->> 'price')::numeric, 0),
         'reinstated "' || s.name || '"', now()
  from jsonb_array_elements(s.income -> 'forecasts') f;

  -- Explicit ids were inserted above; move the id counter past them so new
  -- lines added on the Forecasting page don't collide.
  perform setval(pg_get_serial_sequence('forecast_lines', 'id'),
                 greatest(coalesce((select max(id) from forecast_lines), 0), 1));
end $$;

revoke all on function save_burn_scenario(text) from public, anon;
revoke all on function reinstate_burn_scenario(uuid) from public, anon;
grant execute on function save_burn_scenario(text) to authenticated;
grant execute on function reinstate_burn_scenario(uuid) to authenticated;
