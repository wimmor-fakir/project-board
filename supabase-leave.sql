-- Run this once in your Supabase project's SQL Editor, in addition to
-- supabase-setup.sql. Creates the table behind the Leave page.
--
-- One row per person: bop is their manually-entered Balance at start Of
-- Period, and payspace_entitlement is their manually-entered entitlement
-- for the current cycle (defaults to 25, editable per person — despite
-- the name, this is not synced from PaySpace, since PaySpace's own
-- entitlement endpoint only reports a value for "Employee Defined" leave
-- schemes and is often blank). The page computes EOP (End of Period) as
-- bop + payspace_entitlement - <PaySpace Applications for the current
-- cycle> — nothing here stores that derived total.
--
-- payspace_employee_number is the one-time mapping to that person's
-- PaySpace EmployeeNumber, used both for that EOP calculation and to
-- show the read-only PaySpace Applications figure (see the payspace Edge
-- Function).

create table if not exists leave_balances (
  person_name text primary key,
  bop numeric not null default 0,
  payspace_entitlement numeric not null default 25,
  payspace_employee_number text,
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
