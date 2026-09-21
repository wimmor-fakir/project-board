-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the table behind the Leave page.
--
-- One row per person: their leave entitlement (days allocated),
-- applications (days applied for/taken), and adjustments (a manual
-- correction, positive or negative). The page computes a running
-- balance (entitlement - applications + adjustments) from these —
-- nothing here stores that derived total.

create table if not exists leave_balances (
  person_name text primary key,
  entitlement numeric not null default 0,
  applications numeric not null default 0,
  adjustments numeric not null default 0,
  updated_by text,
  updated_at timestamptz not null default now()
);

alter table leave_balances enable row level security;

drop policy if exists "Signed-in users can read leave balances" on leave_balances;
create policy "Signed-in users can read leave balances"
  on leave_balances for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add leave balances" on leave_balances;
create policy "Signed-in users can add leave balances"
  on leave_balances for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update leave balances" on leave_balances;
create policy "Signed-in users can update leave balances"
  on leave_balances for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');
