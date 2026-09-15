-- Run this once in your Supabase project's SQL Editor
-- (Supabase dashboard -> SQL Editor -> New query -> paste this -> Run)

create table if not exists board_state (
  id text primary key,
  payload jsonb not null,
  updated_at timestamptz not null default now()
);

alter table board_state enable row level security;

create policy "Signed-in users can read board state"
  on board_state for select
  using (auth.role() = 'authenticated');

create policy "Signed-in users can insert board state"
  on board_state for insert
  with check (auth.role() = 'authenticated');

create policy "Signed-in users can update board state"
  on board_state for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

-- Lets signed-in browsers receive live updates when someone else saves
alter publication supabase_realtime add table board_state;
