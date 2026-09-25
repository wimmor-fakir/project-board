-- Run this once in your Supabase project's SQL Editor, after:
--   1. supabase-sim-daily-balances.sql has been run, and
--   2. the sim-cards Edge Function has been (re)deployed with a CRON_SECRET
--      secret set (Edge Functions -> sim-cards -> Secrets). Use any random
--      string for it -- a password generator's output is fine.
--   3. "Verify JWT" has been turned OFF for the sim-cards function
--      (Edge Functions -> sim-cards -> Details). This call carries no
--      signed-in user, so with it on, Supabase rejects every scheduled run
--      with 401 UNAUTHORIZED_NO_AUTH_HEADER before the function even runs.
--      The function checks CRON_SECRET / the user's access itself.
--
-- Schedules a daily call to the sim-cards function so it records that
-- day's balance for every SIM even if nobody opens the SIM Cards page --
-- otherwise a quiet day leaves a gap in the history recharge detection
-- relies on.
--
-- BEFORE RUNNING: replace both placeholders below --
--   <YOUR-CRON-SECRET>  with the exact value you set as CRON_SECRET
--   <YOUR-PROJECT-REF>  with your Supabase project ref (already
--                       "nhgagxdhpdckxnqsbyxw" for this project -- check
--                       Project Settings -> API -> Project URL if this app
--                       ever moves to a different Supabase project)
--
-- Never commit this file to GitHub with the real secret filled in -- run
-- it straight from the SQL Editor, the same way SIMCONTROL_API_KEY etc.
-- are only ever typed into Supabase's own dashboard.

-- pg_cron (the scheduler) and pg_net (lets a scheduled job make an HTTP
-- call) are both official Supabase extensions -- enable them if this
-- errors with a permissions message, use Database -> Extensions in the
-- dashboard instead and search for "pg_cron" / "pg_net".
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'sim-cards-daily-balance-snapshot',
  '0 2 * * *', -- 02:00 UTC daily = 04:00 SAST -- edit the two numbers to change the time
  $$
  select net.http_post(
    url := 'https://<YOUR-PROJECT-REF>.supabase.co/functions/v1/sim-cards',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-cron-secret', '<YOUR-CRON-SECRET>'
    ),
    body := '{}'::jsonb
  );
  $$
);

-- To check it's registered:
--   select * from cron.job where jobname = 'sim-cards-daily-balance-snapshot';
--
-- To see whether it's actually been firing:
--   select * from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'sim-cards-daily-balance-snapshot')
--   order by start_time desc limit 10;
-- ("succeeded" there only means the call was sent. To see what the
-- function answered -- kept for about 6 hours -- look for status_code 200:)
--   select created, status_code, left(content::text, 200)
--   from net._http_response order by created desc limit 5;
--
-- To stop it:
--   select cron.unschedule('sim-cards-daily-balance-snapshot');
--
-- Re-running this whole script is safe -- cron.schedule updates the
-- existing job by name instead of creating a duplicate.
