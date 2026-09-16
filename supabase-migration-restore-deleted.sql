-- Run this once in your Supabase project's SQL Editor if you already ran
-- supabase-activity-log.sql before this update. Adds the column the
-- Activity page's new "Restore" button needs to bring back a deleted
-- action item. Safe to run even if the column already exists.

alter table action_change_log add column if not exists payload jsonb;
