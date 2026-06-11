-- event_types.sql — per-type phases & fields as DATA.
-- Apply order: schema.sql -> social_layer.sql -> event_types.sql (this file)
-- -> crews.sql -> polls.sql.
--
-- Event types are DEVELOPER-defined (the event_type enum). Their workflows
-- (phases) and type-specific fields live in seed tables here — NOT in Dart and
-- NOT in a runtime builder. The client renders the workflow and forms from
-- these tables; it must never hardcode the phase list.
--
--  - status is a PHASE KEY, validated by a composite FK
--    (event_type, status) -> event_type_phases(event_type, key). The DB refuses
--    to put an event into a phase its type doesn't have.
--  - New events auto-start at their type's first phase (lowest position).
--  - Phases are a linear ordered sequence (advance by position). There is no
--    transition-graph rule yet; the FK only validates phase-belongs-to-type.
--  - event_type_phases / event_type_fields are app config: users may SELECT
--    only. Fetch once and cache.

-- ────────────────────────────────────────────────────────────────────────────
-- The developer-defined catalogue of event types.
-- ────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'event_type') then
    create type public.event_type as enum ('trip', 'dinner', 'birthday', 'meetup');
  end if;
end$$;

-- Convert events.event_type (text in schema.sql) to the enum so the composite
-- FK below lines up on column types. Safe to re-run.
do $$
begin
  if (select data_type from information_schema.columns
      where table_schema='public' and table_name='events' and column_name='event_type') <> 'USER-DEFINED'
  then
    alter table public.events
      alter column event_type type public.event_type using event_type::public.event_type;
  end if;
end$$;

-- ────────────────────────────────────────────────────────────────────────────
-- event_type_phases — the workflow for each type. (event_type, key) is unique
-- so it can be the target of the composite FK from events.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.event_type_phases (
  event_type public.event_type not null,
  key        text not null,
  label      text not null,
  position   integer not null,
  is_terminal boolean not null default false,
  primary key (event_type, key),
  unique (event_type, position)
);

-- Human label for a status key within an event's type; falls back to the raw
-- key. Used by the event-history trigger (schema.sql) — it lives HERE because
-- it needs event_type_phases + the enum, which don't exist when schema.sql is
-- applied to a fresh database. Signature takes text (callers may pass the enum;
-- Postgres resolves it) and matches the deployed `event_history` migration —
-- do NOT change it to the enum type or a re-apply would create a second
-- ambiguous overload.
create or replace function public.status_label(p_event_type text, p_key text)
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    (select label from public.event_type_phases
       where event_type = p_event_type::public.event_type and key = p_key),
    p_key);
$$;

-- ────────────────────────────────────────────────────────────────────────────
-- event_type_fields — type-specific property definitions. Values live in
-- events.properties (JSONB), keyed by `key`.
-- ────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'field_datatype') then
    create type public.field_datatype as enum ('text', 'number', 'date', 'bool', 'choice');
  end if;
end$$;

create table if not exists public.event_type_fields (
  event_type  public.event_type not null,
  key         text not null,
  label       text not null,
  datatype    public.field_datatype not null,
  is_required boolean not null default false,
  position    integer not null,
  options     jsonb,  -- for datatype 'choice': array of allowed string values
  primary key (event_type, key),
  unique (event_type, position)
);

-- ════════════════════════════════════════════════════════════════════════════
-- Composite FK: an event's status must be a phase that BELONGS TO its type.
-- Added here (not in schema.sql) because it depends on event_type_phases.
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'events_status_belongs_to_type'
  ) then
    alter table public.events
      add constraint events_status_belongs_to_type
      foreign key (event_type, status)
      references public.event_type_phases (event_type, key);
  end if;
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- Auto-start at the first phase: when an event is inserted without a status (or
-- a NULL status), set it to its type's lowest-position phase. Runs BEFORE the
-- composite FK is checked, so a freshly created event is always FK-valid.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.set_initial_phase()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status is null then
    select key into new.status
    from public.event_type_phases
    where event_type = new.event_type
    order by position asc
    limit 1;

    if new.status is null then
      raise exception 'event_type % has no phases defined', new.event_type
        using errcode = 'foreign_key_violation';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_initial_phase on public.events;
create trigger trg_set_initial_phase
  before insert on public.events
  for each row execute function public.set_initial_phase();

-- ════════════════════════════════════════════════════════════════════════════
-- RLS — config tables are read-only to all authenticated users.
-- ════════════════════════════════════════════════════════════════════════════
alter table public.event_type_phases enable row level security;
alter table public.event_type_fields enable row level security;

drop policy if exists event_type_phases_select on public.event_type_phases;
create policy event_type_phases_select on public.event_type_phases
  for select to authenticated using (true);

drop policy if exists event_type_fields_select on public.event_type_fields;
create policy event_type_fields_select on public.event_type_fields
  for select to authenticated using (true);
-- (no insert/update/delete policies => writes are denied for normal users;
--  seed data below is applied by the migration role, which bypasses RLS.)

-- ════════════════════════════════════════════════════════════════════════════
-- SEED — phases & fields per type. Idempotent (upsert on PK).
-- Phase keys are shared where the meaning is the same, but each type declares
-- its own ordered set; the client reads exactly these.
-- ════════════════════════════════════════════════════════════════════════════

-- ── TRIP ──────────────────────────────────────────────────────────────────--
insert into public.event_type_phases (event_type, key, label, position, is_terminal) values
  ('trip', 'idea',      'Idea',       1, false),
  ('trip', 'planning',  'Planning',   2, false),
  ('trip', 'booked',    'Booked',     3, false),
  ('trip', 'on_trip',   'On the trip',4, false),
  ('trip', 'done',      'Done',       5, true),
  ('trip', 'cancelled', 'Cancelled',  6, true)
on conflict (event_type, key) do update
  set label = excluded.label, position = excluded.position, is_terminal = excluded.is_terminal;

insert into public.event_type_fields (event_type, key, label, datatype, is_required, position, options) values
  ('trip', 'destination', 'Destination', 'text',   true,  1, null),
  ('trip', 'depart_on',   'Departure',   'date',   false, 2, null),
  ('trip', 'return_on',   'Return',      'date',   false, 3, null),
  ('trip', 'budget',      'Budget / person', 'number', false, 4, null),
  ('trip', 'transport',   'Transport',   'choice', false, 5, '["car","train","plane","other"]'::jsonb)
on conflict (event_type, key) do update
  set label = excluded.label, datatype = excluded.datatype,
      is_required = excluded.is_required, position = excluded.position, options = excluded.options;

-- ── DINNER ────────────────────────────────────────────────────────────────--
insert into public.event_type_phases (event_type, key, label, position, is_terminal) values
  ('dinner', 'idea',      'Idea',      1, false),
  ('dinner', 'planning',  'Planning',  2, false),
  ('dinner', 'confirmed', 'Confirmed', 3, false),
  ('dinner', 'done',      'Done',      4, true),
  ('dinner', 'cancelled', 'Cancelled', 5, true)
on conflict (event_type, key) do update
  set label = excluded.label, position = excluded.position, is_terminal = excluded.is_terminal;

insert into public.event_type_fields (event_type, key, label, datatype, is_required, position, options) values
  ('dinner', 'cuisine',   'Cuisine',           'text',   false, 1, null),
  ('dinner', 'host',      'Host / venue',      'text',   false, 2, null),
  ('dinner', 'headcount', 'Expected headcount','number', false, 3, null),
  ('dinner', 'byob',      'BYOB',              'bool',   false, 4, null)
on conflict (event_type, key) do update
  set label = excluded.label, datatype = excluded.datatype,
      is_required = excluded.is_required, position = excluded.position, options = excluded.options;

-- ── BIRTHDAY ──────────────────────────────────────────────────────────────--
insert into public.event_type_phases (event_type, key, label, position, is_terminal) values
  ('birthday', 'idea',      'Idea',      1, false),
  ('birthday', 'planning',  'Planning',  2, false),
  ('birthday', 'confirmed', 'Confirmed', 3, false),
  ('birthday', 'celebrated','Celebrated',4, true),
  ('birthday', 'cancelled', 'Cancelled', 5, true)
on conflict (event_type, key) do update
  set label = excluded.label, position = excluded.position, is_terminal = excluded.is_terminal;

insert into public.event_type_fields (event_type, key, label, datatype, is_required, position, options) values
  ('birthday', 'celebrant',   'Whose birthday', 'text',   true,  1, null),
  ('birthday', 'is_surprise', 'Surprise party', 'bool',   false, 2, null),
  ('birthday', 'theme',       'Theme',          'text',   false, 3, null),
  ('birthday', 'cake',        'Cake plan',      'text',   false, 4, null)
on conflict (event_type, key) do update
  set label = excluded.label, datatype = excluded.datatype,
      is_required = excluded.is_required, position = excluded.position, options = excluded.options;

-- ── MEETUP ────────────────────────────────────────────────────────────────--
insert into public.event_type_phases (event_type, key, label, position, is_terminal) values
  ('meetup', 'idea',      'Idea',      1, false),
  ('meetup', 'planning',  'Planning',  2, false),
  ('meetup', 'confirmed', 'Confirmed', 3, false),
  ('meetup', 'done',      'Done',      4, true),
  ('meetup', 'cancelled', 'Cancelled', 5, true)
on conflict (event_type, key) do update
  set label = excluded.label, position = excluded.position, is_terminal = excluded.is_terminal;

insert into public.event_type_fields (event_type, key, label, datatype, is_required, position, options) values
  ('meetup', 'topic',    'Topic',    'text',   false, 1, null),
  ('meetup', 'venue',    'Venue',    'text',   false, 2, null),
  ('meetup', 'capacity', 'Capacity', 'number', false, 3, null)
on conflict (event_type, key) do update
  set label = excluded.label, datatype = excluded.datatype,
      is_required = excluded.is_required, position = excluded.position, options = excluded.options;
