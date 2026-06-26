-- crews.sql — SHARED, VISIBLE groups (Type 2). Apply AFTER social_layer.sql.
--
-- Two distinct "group" concepts live in this app:
--
--   friend_groups (social_layer.sql)  — Type 1: OWNER-PRIVATE selection groups.
--       Members don't know they're in one and can't see each other. A pure
--       shortcut for adding several friends to an event at once.
--
--   crews (this file)                 — Type 2: SHARED, VISIBLE circles. The
--       owner adds members (no consent step) and EVERY member can see the full
--       roster and that they belong. A persistent visible group ("Roommates").
--
-- They are SEPARATE tables on purpose: their visibility rules diverge (owner-only
-- vs. all-members-can-read), so a single table with a `kind` flag would make
-- every policy conditional and easy to get wrong.
--
-- THE CARDINAL RULE still holds, by construction: crews carry NO event_id and
-- nothing ties events/event_members to crews. Crew membership reveals only WHO
-- is in the crew — never anyone's events, RSVPs, or calendar. A crew can be
-- added to an event only by EXPANDING it into individual event_members rows at
-- add-time (assign_crew_to_event), a one-time snapshot; the crew is never the
-- permission. rls_tests.sql TEST 9 proves a crew co-member who is a surprise
-- target still sees nothing of the surprise.

-- ────────────────────────────────────────────────────────────────────────────
-- Tables
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.crews (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  created_at timestamptz not null default now()
);

create index if not exists crews_owner_idx on public.crews (owner_id);

create table if not exists public.crew_members (
  crew_id    uuid not null references public.crews(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  added_by   uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (crew_id, user_id)
);

create index if not exists crew_members_user_idx on public.crew_members (user_id);

-- ════════════════════════════════════════════════════════════════════════════
-- is_crew_member — "is auth.uid() a member of this crew?" SECURITY DEFINER so it
-- can read crew_members regardless of the caller's RLS — this is what lets the
-- crew_members SELECT policy admit ALL members (not just the owner) without the
-- policy recursing into itself. Same pattern as is_event_member.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.is_crew_member(p_crew uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.crew_members m
    where m.crew_id = p_crew
      and m.user_id = auth.uid()
  );
$$;

revoke all on function public.is_crew_member(uuid) from public;
grant execute on function public.is_crew_member(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- assign_crew_to_event — expand a crew into individual event_members rows.
-- Modeled on assign_group_to_event: caller must OWN the crew AND be an ORGANIZER
-- of the event. One-time snapshot of the crew's CURRENT members. The
-- surprise-target guard trigger still fires per row; we swallow its
-- check_violation so a crew containing the target simply skips that one row.
-- Returns the count actually added.
--
-- DIFFERENCE from assign_group_to_event: crews do NOT require friendship. Crew
-- membership is the owner's explicit, mutually-visible choice, so every current
-- member is expanded (still organizer-gated, still surprise-guarded).
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.assign_crew_to_event(p_crew uuid, p_event uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me    uuid := auth.uid();
  v_added int := 0;
  r       record;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = 'P0001';
  end if;

  -- Caller must own the crew.
  if not exists (select 1 from public.crews c
                 where c.id = p_crew and c.owner_id = v_me) then
    raise exception 'crew % not found or not owned by caller', p_crew
      using errcode = 'insufficient_privilege';
  end if;

  -- Caller must be an organizer of the target event.
  if not public.is_event_organizer(p_event) then
    raise exception 'must be an organizer of event % to add members', p_event
      using errcode = 'insufficient_privilege';
  end if;

  for r in
    select cm.user_id from public.crew_members cm where cm.crew_id = p_crew
  loop
    begin
      insert into public.event_members (event_id, user_id, role, added_by)
      values (p_event, r.user_id, 'member', v_me)
      on conflict (event_id, user_id) do nothing;
      if found then
        v_added := v_added + 1;
      end if;
    exception
      when check_violation then
        -- surprise-target guard (or similar) rejected this row; skip it.
        continue;
    end;
  end loop;

  return v_added;
end;
$$;

revoke all on function public.assign_crew_to_event(uuid, uuid) from public;
grant execute on function public.assign_crew_to_event(uuid, uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════════════
alter table public.crews        enable row level security;
alter table public.crew_members enable row level security;

-- ── crews ── owner OR any member may SEE the crew; only the owner may write.
drop policy if exists crews_select on public.crews;
create policy crews_select on public.crews
  for select to authenticated
  using (owner_id = auth.uid() or public.is_crew_member(id));

drop policy if exists crews_insert_own on public.crews;
create policy crews_insert_own on public.crews
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists crews_update_own on public.crews;
create policy crews_update_own on public.crews
  for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

drop policy if exists crews_delete_own on public.crews;
create policy crews_delete_own on public.crews
  for delete to authenticated using (owner_id = auth.uid());

-- ── crew_members ── EVERY member may read the full roster (the defining Type-2
-- property — contrast friend_group_members, which is owner-only SELECT). Only
-- the crew's owner may add or remove members.
drop policy if exists crew_members_select on public.crew_members;
create policy crew_members_select on public.crew_members
  for select to authenticated
  using (
    public.is_crew_member(crew_id)
    or exists (select 1 from public.crews c
               where c.id = crew_id and c.owner_id = auth.uid())
  );

drop policy if exists crew_members_insert_owner on public.crew_members;
create policy crew_members_insert_owner on public.crew_members
  for insert to authenticated
  with check (
    exists (select 1 from public.crews c
            where c.id = crew_id and c.owner_id = auth.uid())
  );

drop policy if exists crew_members_delete_owner on public.crew_members;
create policy crew_members_delete_owner on public.crew_members
  for delete to authenticated
  using (
    exists (select 1 from public.crews c
            where c.id = crew_id and c.owner_id = auth.uid())
  );

-- ════════════════════════════════════════════════════════════════════════════
-- Realtime — expose crews tables so the client can stream them. RLS still
-- applies to realtime, so streams only carry rows the caller may see.
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.crews;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.crew_members; exception when duplicate_object then null; end;
  end if;
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- NOTIFICATIONS — the first PER-RECIPIENT table (everything else is
-- shared/member-scoped). Lives here (not schema.sql/social_layer.sql) because
-- notifications.crew_id references public.crews(id), which doesn't exist
-- until this file is applied (apply order: schema.sql -> social_layer.sql ->
-- event_types.sql -> crews.sql (this file) -> polls.sql).
--
-- A user only ever reads their own rows (RLS), and is only ever inserted as a
-- recipient by SECURITY DEFINER triggers, never by a client. No detail jsonb:
-- actor/event/crew names are joined live at read time, so e.g. an event
-- rename is reflected and nothing frozen/stale is stored.
--
-- Safety (why this can't leak a surprise): event_member_added is written by an
-- AFTER INSERT trigger on event_members — the surprise-target guard
-- (reject_surprise_target_member, schema.sql) already makes it impossible for
-- events.surprise_target to ever become an event_members row, so this trigger
-- can never fire for the target. event_confirmed/event_cancelled fan out to
-- event_members rows only, same guarantee. friend_added/crew_added involve no
-- event data at all. And underneath all of that, RLS SELECT
-- (recipient_id = auth.uid()) is the binding property regardless.
-- ════════════════════════════════════════════════════════════════════════════
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id     uuid references public.profiles(id) on delete set null,
  kind         text not null check (kind in (
                 'friend_added','crew_added','event_member_added',
                 'event_cancelled','event_confirmed')),
  event_id     uuid references public.events(id) on delete cascade,
  crew_id      uuid references public.crews(id) on delete cascade,
  read_at      timestamptz,
  created_at   timestamptz not null default now()
);
create index notifications_recipient_idx on public.notifications (recipient_id, created_at desc);

alter table public.notifications enable row level security;

-- SELECT: a user only ever sees their own notifications. This is the binding
-- safety property; everything in the header comment is defense-in-depth on
-- top of it.
drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select to authenticated using (recipient_id = auth.uid());

-- UPDATE: a user may update only their own rows, and the column guard below
-- restricts that to setting read_at (mirrors guard_comment_update's shape).
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create or replace function public.guard_notification_update()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.recipient_id is distinct from old.recipient_id
  or new.actor_id     is distinct from old.actor_id
  or new.kind         is distinct from old.kind
  or new.event_id     is distinct from old.event_id
  or new.crew_id      is distinct from old.crew_id
  or new.created_at   is distinct from old.created_at then
    raise exception 'only read_at may be updated on a notification'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_notification_update on public.notifications;
create trigger trg_guard_notification_update
  before update on public.notifications
  for each row execute function public.guard_notification_update();

-- No client INSERT/DELETE policy — append-only, written only by notify()
-- (SECURITY DEFINER), called from the triggers below. Same tamper-proof shape
-- as log_event_history.
create or replace function public.notify(
  p_recipient uuid, p_actor uuid, p_kind text,
  p_event uuid default null, p_crew uuid default null)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if p_recipient is null or p_recipient = p_actor then
    return;  -- never notify someone about their own action
  end if;
  insert into public.notifications (recipient_id, actor_id, kind, event_id, crew_id)
  values (p_recipient, p_actor, p_kind, p_event, p_crew);
end;
$$;

-- ── friends: mutual add notifies BOTH sides ────────────────────────────────
-- add_friend_by_handle (social_layer.sql) writes BOTH (caller,target) and
-- (target,caller) rows, so this fires twice; each fire notifies friend_id
-- about owner_id (the row's owner is who DID the adding, from that row's
-- perspective).
create or replace function public.notify_friend_added()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.notify(new.friend_id, new.owner_id, 'friend_added');
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_added on public.friends;
create trigger trg_notify_friend_added
  after insert on public.friends
  for each row execute function public.notify_friend_added();

-- ── crew_members: skip the self-add case (an owner adding themselves). ─────
create or replace function public.notify_crew_member_added()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.user_id is distinct from new.added_by then
    perform public.notify(new.user_id, new.added_by, 'crew_added', null, new.crew_id);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_crew_member_added on public.crew_members;
create trigger trg_notify_crew_member_added
  after insert on public.crew_members
  for each row execute function public.notify_crew_member_added();

-- ── event_members: fires once per inserted row regardless of whether it came
-- from a direct insert, assign_group_to_event, or assign_crew_to_event — fan-
-- out is naturally per-row already. Skip the creator's own auto-organizer row
-- (user_id = added_by there, per add_creator_as_organizer in schema.sql).
create or replace function public.notify_event_member_added()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.user_id is distinct from new.added_by then
    perform public.notify(new.user_id, new.added_by, 'event_member_added', new.event_id, null);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_event_member_added on public.event_members;
create trigger trg_notify_event_member_added
  after insert on public.event_members
  for each row execute function public.notify_event_member_added();

-- ── events: status changes. Fan out to every current event_members row.
-- 'event_cancelled': any move TO the 'cancelled' phase (the one
--   cancellation-shaped key every event_type seeds, per event_types.sql).
-- 'event_confirmed': the FIRST time the event's phase position moves from
--   idea/planning (position <= 2) to a later position. Guarded against
--   re-firing on later advances or back-and-forth moves (checked via "does a
--   confirmed notification already exist for this event").
create or replace function public.notify_event_status_change()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_new_pos      integer;
  v_new_terminal boolean;
  v_kind         text := null;
  v_member       uuid;
begin
  if new.status is distinct from old.status then
    select position, is_terminal into v_new_pos, v_new_terminal
      from public.event_type_phases
      where event_type = new.event_type and key = new.status;

    if v_new_terminal and new.status = 'cancelled' then
      v_kind := 'event_cancelled';
    elsif v_new_pos is not null and v_new_pos > 2
          and not exists (
            select 1 from public.notifications
            where event_id = new.id and kind = 'event_confirmed'
          ) then
      v_kind := 'event_confirmed';
    end if;

    if v_kind is not null then
      for v_member in
        select user_id from public.event_members where event_id = new.id
      loop
        perform public.notify(v_member, auth.uid(), v_kind, new.id, null);
      end loop;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_event_status_change on public.events;
create trigger trg_notify_event_status_change
  after update of status on public.events
  for each row execute function public.notify_event_status_change();

-- Expose notifications to realtime so the bell badge updates live (RLS still
-- applies — a user's stream only ever carries their own rows).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
  end if;
end$$;
