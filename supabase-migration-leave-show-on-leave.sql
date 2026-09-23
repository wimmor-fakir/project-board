-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-leave.sql before the Settings page's "Leave page" checkboxes
-- existed.
--
-- Adds the show_on_leave column to leave_balances — whether that person
-- appears in the Leave page's table and calendar. Every existing row
-- defaults to shown, so nothing changes until you untick someone. Safe to
-- run even if you're not sure; it does nothing if the column is already
-- there.

alter table leave_balances add column if not exists show_on_leave boolean not null default true;
