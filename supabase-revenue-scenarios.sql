-- Run this once in your Supabase project's SQL Editor, AFTER
-- supabase-project-forecasts.sql.
--
-- Adds named, date-stamped scenarios to the Revenue Forecasting page. A
-- revenue scenario is a snapshot of every Revenue Forecasting line and its
-- monthly locations/price (forecast_lines + project_forecasts). Reinstating
-- one puts all of them back exactly as saved -- after first auto-saving the
-- current lines as another scenario ("Auto-saved before reinstating ..."),
-- so a reinstate can always be undone.
--
-- Access matches the forecast tables themselves: any signed-in user (the
-- page's "Revenue Forecasting" tick controls who sees the tab). EBITDA
-- Forecasting keeps its own, more restricted scenarios
-- (supabase-burn-scenarios.sql), since those also hold the expenses.
-- Saving and reinstating run as database functions so each happens as one
-- all-or-nothing step, and so reinstated lines keep their original ids.

create table if not exists revenue_scenarios (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by text,
  created_at timestamptz not null default now(),
  income jsonb not null
);

alter table revenue_scenarios enable row level security;

drop policy if exists "Signed-in users can read revenue scenarios" on revenue_scenarios;
create policy "Signed-in users can read revenue scenarios"
  on revenue_scenarios for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can delete revenue scenarios" on revenue_scenarios;
create policy "Signed-in users can delete revenue scenarios"
  on revenue_scenarios for delete
  using (auth.role() = 'authenticated');

-- Snapshot the current Revenue Forecasting lines under p_name. Returns the new id.
create or replace function save_revenue_scenario(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  new_id uuid;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Sign in to save a scenario';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'A scenario needs a name';
  end if;
  insert into revenue_scenarios (name, created_by, income)
  values (
    trim(p_name),
    auth.jwt() ->> 'email',
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

-- Put a saved scenario's lines back, after auto-saving the current ones.
create or replace function reinstate_revenue_scenario(p_scenario_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  s revenue_scenarios%rowtype;
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Sign in to reinstate a scenario';
  end if;
  select * into s from revenue_scenarios where id = p_scenario_id;
  if not found then
    raise exception 'Scenario not found';
  end if;

  perform save_revenue_scenario('Auto-saved before reinstating "' || s.name || '"');

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
  -- lines added on the page don't collide.
  perform setval(pg_get_serial_sequence('forecast_lines', 'id'),
                 greatest(coalesce((select max(id) from forecast_lines), 0), 1));
end $$;

revoke all on function save_revenue_scenario(text) from public, anon;
revoke all on function reinstate_revenue_scenario(uuid) from public, anon;
grant execute on function save_revenue_scenario(text) to authenticated;
grant execute on function reinstate_revenue_scenario(uuid) to authenticated;
