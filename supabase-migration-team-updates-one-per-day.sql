-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-team-updates.sql before "one update per person per day" was
-- added. Makes posting again today amend today's row instead of creating
-- a new one.
--
-- ** Step 2 below deletes data: ** if the same person already has more
-- than one post on the same day from before this change, it keeps only
-- the most recent and removes the older one(s) for that day, so the new
-- one-per-day rule can actually be enforced. Skip steps 2 and 3 if you'd
-- rather keep every historical post and not add that rule.

-- 1. Add the column, backfilling existing rows from when they were posted.
alter table team_updates add column if not exists update_date date;
update team_updates set update_date = created_at::date where update_date is null;
alter table team_updates alter column update_date set default current_date;
alter table team_updates alter column update_date set not null;

-- 2. Remove older same-person/same-day duplicates, keeping the latest.
delete from team_updates a using team_updates b
where a.created_by = b.created_by
  and a.update_date = b.update_date
  and a.id < b.id;

-- 3. Enforce one row per person per day going forward.
alter table team_updates drop constraint if exists team_updates_created_by_update_date_key;
alter table team_updates add constraint team_updates_created_by_update_date_key unique (created_by, update_date);

-- 4. Let people amend their own entry for today (needed for the upsert).
drop policy if exists "Signed-in users can update their own team update" on team_updates;
create policy "Signed-in users can update their own team update"
  on team_updates for update
  using (created_by = (auth.jwt() ->> 'email'))
  with check (created_by = (auth.jwt() ->> 'email'));
