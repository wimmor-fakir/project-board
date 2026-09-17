-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the table behind the Forecasting page — one
-- row per project per month, holding the number of locations and the
-- price per location that month. Revenue is computed in the app as
-- locations x price; nothing here stores a derived total.

create table if not exists project_forecasts (
  project_id text not null,
  month date not null, -- always the 1st of the month
  locations integer not null default 0,
  price numeric not null default 0,
  updated_by text,
  updated_at timestamptz not null default now(),
  primary key (project_id, month)
);

alter table project_forecasts enable row level security;

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
