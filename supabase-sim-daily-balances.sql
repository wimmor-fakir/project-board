-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Stores one row per SIM per day of its data balance,
-- so the sim-cards Edge Function can detect recharges by spotting a day
-- where the balance is higher than the day before (SIMcontrol has no
-- reliable API for reading balance history directly). The sim-cards
-- function writes today's row automatically every time it runs — one
-- write per day per SIM is all that's needed; running it more than once
-- a day just overwrites that day's row with the latest reading.
--
-- History only starts from whenever this table exists, so anything from
-- 1 September 2026 up to when you run this needs to be entered by hand —
-- see the example at the bottom.

create table if not exists sim_daily_balances (
  msisdn text not null,
  date date not null,
  balance_mb numeric not null,
  recorded_at timestamptz not null default now(),
  recorded_by text,
  primary key (msisdn, date)
);

alter table sim_daily_balances enable row level security;

create policy "Signed-in users can read daily balances"
  on sim_daily_balances for select
  using (auth.role() = 'authenticated');

create policy "Signed-in users can insert daily balances"
  on sim_daily_balances for insert
  with check (auth.role() = 'authenticated');

create policy "Signed-in users can update daily balances"
  on sim_daily_balances for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- To backfill historic days (from 1 September 2026 onward), insert one row
-- per SIM per day you have a real balance for, e.g.:
--
--   insert into sim_daily_balances (msisdn, date, balance_mb, recorded_by)
--   values
--     ('27821234567', '2026-09-01', 1024.5, 'manual backfill'),
--     ('27821234567', '2026-09-02', 980.2, 'manual backfill')
--   on conflict (msisdn, date) do update set balance_mb = excluded.balance_mb;
--
-- Find each SIM's msisdn on the SIM Cards page (shown under its name).
