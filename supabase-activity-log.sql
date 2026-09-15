-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Adds a table that records who changed which action
-- item and what changed, for accountability/history purposes.

create table if not exists action_change_log (
  id bigint generated always as identity primary key,
  action_id bigint not null,
  action_code text,
  change_type text not null, -- 'created' | 'updated' | 'deleted'
  summary text not null,
  changed_by text not null, -- the signed-in user's email
  created_at timestamptz not null default now()
);

alter table action_change_log enable row level security;

create policy "Signed-in users can read the change log"
  on action_change_log for select
  using (auth.role() = 'authenticated');

create policy "Signed-in users can add to the change log"
  on action_change_log for insert
  with check (auth.role() = 'authenticated');

-- No update/delete policy on purpose: this is an append-only audit trail.

alter publication supabase_realtime add table action_change_log;
