-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-leave.sql before the Leave page switched from
-- entitlement/applications/adjustments to a single BOP (Balance at start
-- Of Period) field.
--
-- Adds the bop column. Safe to run even if you're not sure; it does
-- nothing if the column is already there.
--
-- Your existing entitlement/applications/adjustments columns and data
-- are left untouched (not dropped) — the app just stops reading/writing
-- them, since EOP is now computed from bop + 25 - PaySpace Applications
-- instead. Ask if you'd like a follow-up migration to drop those columns
-- once you've confirmed you don't need that old data.

alter table leave_balances add column if not exists bop numeric not null default 0;
