-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the tables behind the Forecasting page.
--
-- Each project can have multiple forecasting "lines" (e.g. one project
-- might forecast "Product A" and "Product B" separately) — forecast_lines
-- holds one row per line; project_forecasts holds one row per line per
-- month, with the number of locations and the price per location that
-- month. Revenue is computed in the app as locations x price; nothing
-- here stores a derived total.

create table if not exists forecast_lines (
  id bigint generated always as identity primary key,
  project_id text not null,
  label text not null default 'Line 1',
  sort_order integer not null default 0,
  included_in_chart boolean not null default true,
  created_by text,
  created_at timestamptz not null default now()
);

create table if not exists project_forecasts (
  line_id bigint not null references forecast_lines(id) on delete cascade,
  month date not null, -- always the 1st of the month
  locations integer not null default 0,
  price numeric not null default 0,
  updated_by text,
  updated_at timestamptz not null default now(),
  primary key (line_id, month)
);

alter table forecast_lines enable row level security;
alter table project_forecasts enable row level security;

drop policy if exists "Signed-in users can read forecast lines" on forecast_lines;
create policy "Signed-in users can read forecast lines"
  on forecast_lines for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add forecast lines" on forecast_lines;
create policy "Signed-in users can add forecast lines"
  on forecast_lines for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update forecast lines" on forecast_lines;
create policy "Signed-in users can update forecast lines"
  on forecast_lines for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can delete forecast lines" on forecast_lines;
create policy "Signed-in users can delete forecast lines"
  on forecast_lines for delete
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can read forecasts" on project_forecasts;
create policy "Signed-in users can read forecasts"
  on project_forecasts for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add forecasts" on project_forecasts;
create policy "Signed-in users can add forecasts"
  on project_forecasts for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update forecasts" on project_forecasts;
create policy "Signed-in users can update forecasts"
  on project_forecasts for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
