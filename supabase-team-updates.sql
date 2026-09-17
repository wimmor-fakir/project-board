-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the table behind the Team Update page —
-- a simple, append-only feed anyone with access to that page can post to.

create table if not exists team_updates (
  id bigint generated always as identity primary key,
  text text not null,
  created_by text not null, -- the signed-in user's email
  created_at timestamptz not null default now()
);

alter table team_updates enable row level security;

create policy "Signed-in users can read team updates"
  on team_updates for select
  using (auth.role() = 'authenticated');

create policy "Signed-in users can post team updates"
  on team_updates for insert
  with check (auth.role() = 'authenticated');

-- No update/delete policy on purpose: posts are permanent once made.
