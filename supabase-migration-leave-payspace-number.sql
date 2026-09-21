-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-leave.sql before the PaySpace Employee Number mapping existed.
--
-- Adds the payspace_employee_number column to leave_balances — the
-- one-time mapping from a person to their PaySpace EmployeeNumber, used
-- to show read-only PaySpace figures alongside the manually-entered
-- ones. Safe to run even if you're not sure; it does nothing if the
-- column is already there.

alter table leave_balances add column if not exists payspace_employee_number text;
