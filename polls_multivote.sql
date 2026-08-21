-- polls_multivote.sql — lets a member vote for SEVERAL options in one poll.
--
-- Run this in the Supabase SQL editor BEFORE (or together with) shipping the
-- matching app build. Until it is applied, the old
-- `unique (poll_id, user_id)` constraint rejects a second vote and the app
-- surfaces a unique-violation error instead of adding the vote.
--
-- Two changes:
--   1. The uniqueness key gains option_id, so "one vote per option per member"
--      replaces "one vote per poll per member". A member still cannot vote for
--      the same option twice, which is what makes the tap-to-toggle in the app
--      safe against double taps.
--   2. A voter-count RPC. Once a member can pick several options, the number of
--      VOTES stops equalling the number of VOTERS, and the polls preview on the
--      event page wants voters. It has to be an RPC for the same reason the
--      tallies are: while a poll is open, RLS shows a member only their own
--      vote rows for the whole event, so the count is done in the database.
--      Returning only a COUNT keeps that promise — it never reveals who voted.

begin;

-- ── 1. one vote per (poll, member, option) ──────────────────────────────────
-- Existing rows are already unique on (poll_id, user_id), so they satisfy the
-- wider key too — no data has to be deleted.
alter table public.poll_votes
  drop constraint if exists poll_votes_poll_id_user_id_key;

alter table public.poll_votes
  add constraint poll_votes_poll_user_option_key
  unique (poll_id, user_id, option_id);

-- ── 2. distinct voters per poll ─────────────────────────────────────────────
create or replace function public.poll_voter_counts_for_event(p_event uuid)
returns table(poll_id uuid, voters bigint)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not public.is_event_member(p_event) then
    return;  -- not a member: no rows
  end if;
  return query
    select p.id, count(distinct v.user_id)::bigint
    from public.polls p
    left join public.poll_votes v on v.poll_id = p.id
    where p.event_id = p_event
    group by p.id;
end;
$$;

revoke all on function public.poll_voter_counts_for_event(uuid) from public;
grant execute on function public.poll_voter_counts_for_event(uuid) to authenticated;

commit;
