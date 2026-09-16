-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Lets the SIM Cards page's "click to edit" last-recharge
-- date be saved and override whatever (if anything) SIMcontrol's own API
-- reports, since that account may have no recharge history recorded yet.

create table if not exists sim_recharge_overrides (
  msisdn text primary key,
  last_recharge_date date not null,
  updated_at timestamptz not null default now(),
  updated_by text
);

alter table sim_recharge_overrides enable row level security;

create policy "Signed-in users can read recharge overrides"
  on sim_recharge_overrides for select
  using (auth.role() = 'authenticated');

create policy "Signed-in users can set recharge overrides"
  on sim_recharge_overrides for insert
  with check (auth.role() = 'authenticated');

create policy "Signed-in users can update recharge overrides"
  on sim_recharge_overrides for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
