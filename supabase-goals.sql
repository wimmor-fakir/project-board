-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the tables behind the Goals page.
--
-- goals_settings holds a single shared "date for next goals" — the same
-- target date applies to every project's goals, there's no per-project
-- date. project_goals holds up to 3 goal slots per project (slot 1-3);
-- an empty/missing slot just means that goal hasn't been set yet.

create table if not exists goals_settings (
  id text primary key,
  target_date date,
  updated_by text,
  updated_at timestamptz not null default now()
);

create table if not exists project_goals (
  project_id text not null,
  slot integer not null check (slot between 1 and 3),
  text text not null default '',
  updated_by text,
  updated_at timestamptz not null default now(),
  primary key (project_id, slot)
);

alter table goals_settings enable row level security;
alter table project_goals enable row level security;

drop policy if exists "Signed-in users can read goals settings" on goals_settings;
create policy "Signed-in users can read goals settings"
  on goals_settings for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add goals settings" on goals_settings;
create policy "Signed-in users can add goals settings"
  on goals_settings for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update goals settings" on goals_settings;
create policy "Signed-in users can update goals settings"
  on goals_settings for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can read project goals" on project_goals;
create policy "Signed-in users can read project goals"
  on project_goals for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add project goals" on project_goals;
create policy "Signed-in users can add project goals"
  on project_goals for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update project goals" on project_goals;
create policy "Signed-in users can update project goals"
  on project_goals for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
