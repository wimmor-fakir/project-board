-- Run this once in your Supabase project's SQL Editor only if you already
-- ran the original supabase-team-updates.sql (the one with a single free-
-- text "text" column) before Team Update became a 4-question check-in.
-- Safe to run even if you're not sure; it does nothing if already applied.

alter table team_updates add column if not exists how_are_you text;
alter table team_updates add column if not exists whereabouts text;
alter table team_updates add column if not exists priority text;
alter table team_updates add column if not exists needs_help text;

-- The old free-text column is no longer written to by the app, but it's
-- left in place (and any old posts in it) rather than dropped — it just
-- can't stay required, or every new post fails with a not-null violation.
alter table team_updates alter column text drop not null;
