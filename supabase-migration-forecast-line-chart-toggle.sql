-- Run this once in your Supabase project's SQL Editor if you already
-- have the forecast_lines table (from supabase-project-forecasts.sql or
-- supabase-migration-forecast-lines.sql) from before each line could be
-- individually included/excluded from the Forecasting chart.
--
-- Adds the included_in_chart column, defaulting every existing line to
-- true (shown in the chart), which matches how they behaved before this
-- toggle existed. Safe to run even if you're not sure; it does nothing
-- if the column is already there.

alter table forecast_lines add column if not exists included_in_chart boolean not null default true;
