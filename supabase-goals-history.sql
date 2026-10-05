-- Run this once in your Supabase project's SQL Editor, AFTER supabase-goals.sql.
--
-- Keeps the Goals page's goals for each "date for next goals". When someone
-- changes that date, the goals on the page are saved under the date they were
-- for, and the page then shows whatever was saved for the new date (blank if
-- that date has never had goals). Choosing an earlier date again brings its
-- goals back. Nothing is thrown away: a date's saved goals stay until that
-- date is switched away from again, when they are replaced by the then-current
-- ones.
--
-- Saving and switching run as one database function so it is all-or-nothing.
-- The very first time a date is set (no date before it), the goals already
-- entered simply become that date's goals.

create table if not exists project_goals_history (
  target_date date not null,
  project_id text not null,
  slot integer not null check (slot between 1 and 3),
  text text not null default '',
  saved_by text,
  saved_at timestamptz not null default now(),
  primary key (target_date, project_id, slot)
);

alter table project_goals_history enable row level security;

drop policy if exists "Signed-in users can read goals history" on project_goals_history;
create policy "Signed-in users can read goals history"
  on project_goals_history for select
  using (auth.role() = 'authenticated');

-- Switch the Goals page to p_new_date, saving the current date's goals first.
create or replace function change_goals_date(p_new_date date) returns void
language plpgsql security definer set search_path = public as $$
declare
  old_date date;
  who text := auth.jwt() ->> 'email';
begin
  if coalesce(auth.role(), '') <> 'authenticated' then
    raise exception 'Sign in to change the goals date';
  end if;
  if p_new_date is null then
    raise exception 'Pick a date';
  end if;

  select target_date into old_date from goals_settings where id = 'default';
  if old_date is not distinct from p_new_date then
    return;
  end if;

  if old_date is not null then
    -- Save the goals as they are now under the date they were for ...
    delete from project_goals_history where target_date = old_date;
    insert into project_goals_history (target_date, project_id, slot, text, saved_by)
    select old_date, project_id, slot, text, who from project_goals where text <> '';

    -- ... then show the new date's saved goals (none saved = a blank slate).
    delete from project_goals where true; -- "where true": Supabase rejects a bare DELETE
    insert into project_goals (project_id, slot, text, updated_by, updated_at)
    select project_id, slot, text, who, now() from project_goals_history where target_date = p_new_date;
  end if;

  insert into goals_settings (id, target_date, updated_by, updated_at)
  values ('default', p_new_date, who, now())
  on conflict (id) do update
    set target_date = excluded.target_date, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
end $$;

revoke all on function change_goals_date(date) from public, anon;
grant execute on function change_goals_date(date) to authenticated;
