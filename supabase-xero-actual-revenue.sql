-- Run this once in your Supabase project's SQL Editor, AFTER
-- supabase-burn-forecast.sql (it reuses burn_forecast_allowed()).
--
-- Creates the table behind EBITDA Forecasting's actual revenue: one row per
-- month holding that month's Sales from Xero (the Sales income account,
-- accrual basis -- i.e. by invoice date). In a month switched to A (Actual),
-- the page's revenue row -- and so its Burn line -- uses this figure instead
-- of the Revenue Forecasting page's forecast.
--
-- Same access rule as the EBITDA figures themselves: only the admin and
-- people ticked "EBITDA Forecasting" can read it. Nobody can change it from
-- the page -- there are no insert/update policies -- the figures are only
-- loaded here in the SQL Editor, from a separate data script that is never
-- committed (this repo is public). Re-running a newer data script
-- overwrites the months it contains.

create table if not exists xero_actual_revenue (
  month date primary key,               -- first day of the month
  revenue numeric(14, 2) not null,      -- Xero Sales for that month (ZAR, accrual)
  through_date date not null,           -- last day the figure covers (earlier than month-end for a month still in progress)
  refreshed_at timestamptz not null default now()
);

alter table xero_actual_revenue enable row level security;

drop policy if exists "EBITDA Forecasting access can read Xero revenue" on xero_actual_revenue;
create policy "EBITDA Forecasting access can read Xero revenue"
  on xero_actual_revenue for select
  using (burn_forecast_allowed());
