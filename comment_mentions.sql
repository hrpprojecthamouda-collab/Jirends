-- Comment mentions: tag an event member in a comment, they get a bell
-- notification.
--
-- CARDINAL RULE — this is the whole design constraint. A mention notification
-- names an event, so it may only ever reach somebody who can already SEE that
-- event. The trigger therefore resolves a handle to a user and then requires
-- `is_event_member(...)` before notifying; a non-member mention is parsed,
-- found to be a non-member, and silently dropped.
--
-- That is deliberately not an error. Erroring would itself be a side channel:
-- "you cannot tag Dave here" tells the author Dave is not in the event, and on
-- a surprise event tells them who the target is. Silence tells them nothing.
--
-- The surprise target is covered twice over, as elsewhere: they are not in
-- event_members, and is_event_member is what gates the notify.

-- 1. A new notification kind. The CHECK is rewritten wholesale because Postgres
--    has no "add value to a check constraint".
alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in (
    'friend_added','crew_added','event_member_added',
    'event_cancelled','event_confirmed','expense_added',
    'comment_mention'));

-- 2. Which comment the mention was in, so the bell can open the right thread.
alter table public.notifications
  add column if not exists comment_id uuid references public.comments(id) on delete cascade;

-- 3. Parse @nickname#tagline out of a comment and notify the members among them.
--
-- Handles are (nickname, tagline) and both are free text, so the pattern is
-- deliberately conservative: letters, digits, underscore, hyphen and dot. A
-- handle containing anything else simply will not be matched, which fails
-- closed — no notification — rather than matching something unintended.
create or replace function public.notify_comment_mentions()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  m        text[];
  v_user   uuid;
  v_seen   uuid[] := '{}';
begin
  for m in
    select regexp_matches(
             new.body,
             '@([A-Za-z0-9_.-]+)#([A-Za-z0-9_.-]+)',
             'g')
  loop
    select id into v_user
      from public.profiles
     where nickname = m[1] and tagline = m[2];

    if v_user is null then
      continue;                       -- no such handle
    end if;
    if v_user = any(v_seen) then
      continue;                       -- mentioned twice in one comment
    end if;
    -- THE GATE: only somebody who can already see this event may be told
    -- about it. Non-members are skipped in silence, on purpose.
    if not public.is_event_member(new.event_id) then
      continue;                       -- author cannot even see it (paranoia)
    end if;
    if not exists (
      select 1 from public.event_members
       where event_id = new.event_id and user_id = v_user
    ) then
      continue;
    end if;

    v_seen := v_seen || v_user;
    -- notify() already refuses recipient = actor, so tagging yourself is a
    -- no-op without a special case here.
    insert into public.notifications
      (recipient_id, actor_id, kind, event_id, comment_id)
    select v_user, new.author_id, 'comment_mention', new.event_id, new.id
     where v_user is distinct from new.author_id;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_notify_comment_mentions on public.comments;
create trigger trg_notify_comment_mentions
  after insert on public.comments
  for each row execute function public.notify_comment_mentions();
