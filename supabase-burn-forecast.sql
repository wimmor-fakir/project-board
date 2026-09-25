-- Run this once in your Supabase project's SQL Editor. Creates the table
-- behind the Burn Forecasting page.
--
-- The whole sheet (columns, sections, accounts, figures, notes) is stored
-- as one JSON document in a single row (id = 'main'). The figures are
-- company financials (payroll included), so -- unlike every other table in
-- this app, which any signed-in user can read -- the database itself only
-- lets through:
--   * the admin account (wim@hawktivity.com), and
--   * people the admin has ticked "Burn Forecasting" for under Settings ->
--     User management.
-- That tick is read from app_metadata, which only the manage-users Edge
-- Function (service role) can write -- unlike user_metadata, a user can't
-- grant it to themselves. Someone newly ticked may need to sign out and
-- back in before their access takes effect (it's carried in their sign-in
-- token, refreshed about hourly).
--
-- The figures themselves are NOT in this file (this repo is public). Load
-- them with the separate data script, run straight from the SQL Editor.

create table if not exists burn_forecast (
  id text primary key,
  payload jsonb not null,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table burn_forecast enable row level security;

create or replace function burn_forecast_allowed() returns boolean
language sql stable as $$
  select coalesce(auth.jwt() ->> 'email', '') = 'wim@hawktivity.com'
      or coalesce((auth.jwt() -> 'app_metadata' -> 'page_access' ->> 'burnforecast')::boolean, false)
$$;

drop policy if exists "Burn Forecasting access can read" on burn_forecast;
create policy "Burn Forecasting access can read"
  on burn_forecast for select
  using (burn_forecast_allowed());

drop policy if exists "Burn Forecasting access can add" on burn_forecast;
create policy "Burn Forecasting access can add"
  on burn_forecast for insert
  with check (burn_forecast_allowed());

drop policy if exists "Burn Forecasting access can update" on burn_forecast;
create policy "Burn Forecasting access can update"
  on burn_forecast for update
  using (burn_forecast_allowed())
  with check (burn_forecast_allowed());
