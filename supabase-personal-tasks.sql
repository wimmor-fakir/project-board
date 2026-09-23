-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the tables behind the My Tasks page.
--
-- personal_tasks holds each user's private to-do items. Unlike every other
-- table in this app (readable by any signed-in user), its security rules
-- only ever let a user read, add, change or delete THEIR OWN rows — so
-- nobody else can see someone's private tasks, even by calling the
-- database directly with their own sign-in.
--
-- personal_task_settings remembers, per user, which person on the board
-- they are (for the page's "Assigned to me in the action list" section).
-- Same own-rows-only rules.

create table if not exists personal_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  text text not null,
  due_date date,
  done boolean not null default false,
  done_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists personal_tasks_user_id_idx on personal_tasks (user_id);

alter table personal_tasks enable row level security;

drop policy if exists "Users can read their own tasks" on personal_tasks;
create policy "Users can read their own tasks"
  on personal_tasks for select
  using (user_id = auth.uid());

drop policy if exists "Users can add their own tasks" on personal_tasks;
create policy "Users can add their own tasks"
  on personal_tasks for insert
  with check (user_id = auth.uid());

drop policy if exists "Users can update their own tasks" on personal_tasks;
create policy "Users can update their own tasks"
  on personal_tasks for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Users can delete their own tasks" on personal_tasks;
create policy "Users can delete their own tasks"
  on personal_tasks for delete
  using (user_id = auth.uid());

create table if not exists personal_task_settings (
  user_id uuid primary key default auth.uid() references auth.users(id) on delete cascade,
  person_name text,
  updated_at timestamptz not null default now()
);

alter table personal_task_settings enable row level security;

drop policy if exists "Users can read their own task settings" on personal_task_settings;
create policy "Users can read their own task settings"
  on personal_task_settings for select
  using (user_id = auth.uid());

drop policy if exists "Users can add their own task settings" on personal_task_settings;
create policy "Users can add their own task settings"
  on personal_task_settings for insert
  with check (user_id = auth.uid());

drop policy if exists "Users can update their own task settings" on personal_task_settings;
create policy "Users can update their own task settings"
  on personal_task_settings for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
