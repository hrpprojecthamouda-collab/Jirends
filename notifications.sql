-- notifications.sql — the per-recipient notification table, its RLS, and the
-- triggers that write it. Apply AFTER social_layer.sql.
--
-- Was crews.sql. Crews (shared, visible circles) were removed on 2026-08-23:
-- two "group" concepts with divergent visibility rules meant two tables, two
-- RLS models and two screens for one user-facing idea, and friend_groups keeps
-- the part that mattered — adding several people to an event in one tap.
-- The notification system lived in the same file and survives unchanged.

-- ════════════════════════════════════════════════════════════════════════════
-- NOTIFICATIONS — the first PER-RECIPIENT table (everything else is
-- shared/member-scoped). Kept in its own file, applied after social_layer.sql
-- so the friends triggers it hangs off already exist.
--
-- A user only ever reads their own rows (RLS), and is only ever inserted as a
-- recipient by SECURITY DEFINER triggers, never by a client. No detail jsonb:
-- actor and event names are joined live at read time, so e.g. an event rename
-- is reflected and nothing frozen/stale is stored.
--
-- Safety: event_member_added is written by an AFTER INSERT trigger on
-- event_members, so it can only ever name somebody who has just become a
-- member. event_confirmed/event_cancelled fan out to event_members rows only,
-- same guarantee. friend_added involves no event data at all. And
-- underneath all of that, RLS SELECT (recipient_id = auth.uid()) is the
-- binding property regardless.
-- ════════════════════════════════════════════════════════════════════════════
create table public.notifications (
  id           uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  actor_id     uuid references public.profiles(id) on delete set null,
  kind         text not null check (kind in (
                 'friend_added','event_member_added',
                 'event_cancelled','event_confirmed','expense_added',
                 'comment_mention')),
  event_id     uuid references public.events(id) on delete cascade,
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
  p_event uuid default null)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if p_recipient is null or p_recipient = p_actor then
    return;  -- never notify someone about their own action
  end if;
  insert into public.notifications (recipient_id, actor_id, kind, event_id)
  values (p_recipient, p_actor, p_kind, p_event);
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
  -- add_friend_by_handle writes BOTH directions, so this fires twice. The
  -- mirror row (owner = the person who was added) would notify the initiator
  -- that their own target "added them", which they plainly know. Only the row
  -- the caller owns produces a notification.
  -- Applied live as `friend_added_notify_only_the_added_side`.
  if new.owner_id is distinct from auth.uid() then
    return new;
  end if;
  perform public.notify(new.friend_id, new.owner_id, 'friend_added');
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_added on public.friends;
create trigger trg_notify_friend_added
  after insert on public.friends
  for each row execute function public.notify_friend_added();

-- ── event_members: fires once per inserted row regardless of whether it came
-- from a direct insert or assign_group_to_event — fan-
-- out is naturally per-row already. Skip the creator's own auto-organizer row
-- (user_id = added_by there, per add_creator_as_organizer in schema.sql).
create or replace function public.notify_event_member_added()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.user_id is distinct from new.added_by then
    perform public.notify(new.user_id, new.added_by, 'event_member_added', new.event_id);
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
    elsif v_new_pos is not null and v_new_pos > 2 then
      v_kind := 'event_confirmed';
    end if;

    if v_kind is not null then
      -- SUPERSEDE rather than suppress. The old rule was "don't re-notify if a
      -- confirmed notification already exists", which meant a later cancel sat
      -- in the bell BESIDE the earlier confirm and the reader had to work out
      -- which won. Deleting the event's previous status notifications first
      -- leaves exactly one, always the current state.
      -- Applied live as `event_status_notification_supersedes_previous`.
      delete from public.notifications
       where event_id = new.id
         and kind in ('event_confirmed', 'event_cancelled');

      for v_member in
        select user_id from public.event_members where event_id = new.id
      loop
        perform public.notify(v_member, auth.uid(), v_kind, new.id);
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
--
-- REPLICA IDENTITY FULL is not optional here. The badge subscribes with a
-- filter on recipient_id, and under the default identity an UPDATE ships only
-- the primary key in its old row — so Postgres cannot match the filter and the
-- event is dropped. The read/unread transition is an UPDATE, which is to say
-- exactly the change the badge exists to follow. Same trap as reactions, where
-- a filtered DELETE meant the counter only ever went up.
alter table public.notifications replica identity full;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.notifications; exception when duplicate_object then null; end;
  end if;
end$$;
