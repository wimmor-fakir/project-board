-- Run this once in your Supabase project's SQL Editor if you already ran
-- the original supabase-project-forecasts.sql (the one where
-- project_forecasts was keyed directly by project_id) before multiple
-- forecasting lines per project existed. Safe to run even if you're not
-- sure — every step below only acts if it hasn't already.
--
-- What this does: every project that already has forecast rows gets one
-- "Line 1" created for it, and its existing monthly numbers are moved
-- onto that line — nothing is deleted, a project's old numbers just
-- become its first line instead of being attached to the project
-- directly. After this, add more lines to a project from the
-- Forecasting page itself.

-- 1. Create forecast_lines if it doesn't exist yet.
create table if not exists forecast_lines (
  id bigint generated always as identity primary key,
  project_id text not null,
  label text not null default 'Line 1',
  sort_order integer not null default 0,
  created_by text,
  created_at timestamptz not null default now()
);

alter table forecast_lines enable row level security;

drop policy if exists "Signed-in users can read forecast lines" on forecast_lines;
create policy "Signed-in users can read forecast lines"
  on forecast_lines for select
  using (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can add forecast lines" on forecast_lines;
create policy "Signed-in users can add forecast lines"
  on forecast_lines for insert
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can update forecast lines" on forecast_lines;
create policy "Signed-in users can update forecast lines"
  on forecast_lines for update
  using (auth.role() = 'authenticated')
  with check (auth.role() = 'authenticated');

drop policy if exists "Signed-in users can delete forecast lines" on forecast_lines;
create policy "Signed-in users can delete forecast lines"
  on forecast_lines for delete
  using (auth.role() = 'authenticated');

-- 2. Nothing left to migrate if project_forecasts is still on the new
--    schema (line_id already the key) or doesn't have a project_id
--    column at all — the rest of this script only runs against the old
--    shape.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'project_forecasts' and column_name = 'project_id'
  ) then

    -- 3. One default line per project that already has forecast rows.
    insert into forecast_lines (project_id, label, sort_order)
    select distinct pf.project_id, 'Line 1', 0
    from project_forecasts pf
    where not exists (
      select 1 from forecast_lines fl where fl.project_id = pf.project_id
    );

    -- 4. Point every existing row at that project's default line.
    alter table project_forecasts add column if not exists line_id bigint references forecast_lines(id) on delete cascade;
    update project_forecasts pf
    set line_id = fl.id
    from forecast_lines fl
    where fl.project_id = pf.project_id and pf.line_id is null;

    -- 5. Swap the primary key from (project_id, month) to (line_id, month).
    alter table project_forecasts drop constraint if exists project_forecasts_pkey;
    alter table project_forecasts alter column line_id set not null;
    alter table project_forecasts add primary key (line_id, month);

    -- 6. Drop the now-redundant column.
    alter table project_forecasts drop column if exists project_id;

  end if;
end $$;
