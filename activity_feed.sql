-- activity_feed.sql — the two activity-surfacing changes that cannot be done
-- from the client.
--
-- Run in the Supabase SQL editor. Safe to re-run.
--
-- The other four requests (reply.posted, poll.closed, poll.reopened,
-- attachment.uploaded in the feed) needed no schema change: replies were
-- already fetched and merely mislabelled, the poll events were already in
-- event_history, and attachments already carry created_at. Only these two need
-- the database.

begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. rsvp.set IN THE FEED — needs a timestamp to exist at all.
--
-- event_members.created_at records when a member was ADDED, not when they
-- answered. Without a separate column an RSVP has no position in a
-- chronological feed: answering today would surface at the time you were
-- invited, days earlier. So: stamp it, and only when the answer actually
-- changes (re-saving the same rsvp must not bump the feed).
-- ════════════════════════════════════════════════════════════════════════════
alter table public.event_members
  add column if not exists rsvp_at timestamptz;

create or replace function public.stamp_rsvp_change()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.rsvp is distinct from old.rsvp then
    new.rsvp_at := now();
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_rsvp_change on public.event_members;
create trigger trg_stamp_rsvp_change
  before update on public.event_members
  for each row execute function public.stamp_rsvp_change();

-- Index the column the feed will order by.
create index if not exists event_members_rsvp_at_idx
  on public.event_members (rsvp_at desc) where rsvp_at is not null;

-- ════════════════════════════════════════════════════════════════════════════
-- 2. expense.added IN THE BELL — notifications are append-only and written
-- solely by notify() (SECURITY DEFINER, no client INSERT policy), so this has
-- to be a trigger.
--
-- VISIBILITY: the fan-out reads event_members and nothing else. A non-member
-- target is never in that table, so an expense on an event hidden from them
-- can never produce a notification that reveals it. notify() additionally
-- refuses to notify an actor about their own action.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.notify_expense_added()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_member uuid;
begin
  for v_member in
    select user_id from public.event_members where event_id = new.event_id
  loop
    perform public.notify(v_member, auth.uid(), 'expense_added', new.event_id, null);
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_notify_expense_added on public.expenses;
create trigger trg_notify_expense_added
  after insert on public.expenses
  for each row execute function public.notify_expense_added();

commit;
