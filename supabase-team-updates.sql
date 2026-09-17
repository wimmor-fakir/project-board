-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the table behind the Team Update page — a
-- daily check-in feed (how you are, whereabouts, priority, help needed)
-- that anyone with access to the page can post to. One row per person
-- per day: posting again the same day amends that day's row instead of
-- creating a new one.

create table if not exists team_updates (
  id bigint generated always as identity primary key,
  update_date date not null default current_date,
  how_are_you text,
  whereabouts text,
  priority text,
  needs_help text,
  created_by text not null, -- the signed-in user's email
  created_at timestamptz not null default now(),
  unique (created_by, update_date)
);

alter table team_updates enable row level security;

drop policy if exists "Signed-in users can read team updates" on team_updates;
create policy "Signed-in users can read team updates"
  on team_updates for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can post team updates" on team_updates;
create policy "Signed-in users can post team updates"
  on team_updates for insert
  with check (auth.role() = 'authenticated');

-- Needed so posting again today amends today's row (an upsert) instead of
-- being rejected — but only your own row, never someone else's.
drop policy if exists "Signed-in users can update their own team update" on team_updates;
create policy "Signed-in users can update their own team update"
  on team_updates for update
  using (created_by = (auth.jwt() ->> 'email'))
  with check (created_by = (auth.jwt() ->> 'email'));
