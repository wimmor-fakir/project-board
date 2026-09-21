-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-leave.sql before PaySpace Entitlement became an editable
-- per-person field.
--
-- Adds the payspace_entitlement column, defaulting every existing row to
-- 25 (the previous flat value used in the EOP formula) — so nothing
-- changes for anyone until you edit their value. Safe to run even if
-- you're not sure; it does nothing if the column is already there.

alter table leave_balances add column if not exists payspace_entitlement numeric not null default 25;
