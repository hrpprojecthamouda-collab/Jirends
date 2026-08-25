-- polls.sql — polls on an event (apply AFTER notifications.sql).
--
-- A poll belongs to an event; members vote (one vote each); the poll's creator
-- closes it. Two resolution modes:
--   majority        — highest-count option wins; a tie => no winner (is_tie).
--   weighted_random — winner drawn at random weighted by vote share, ONCE, in
--                     close_poll() (server-side), and stored. The UI wheel is
--                     cosmetic over the stored winner.
--
-- THE CARDINAL RULE: polls/options/votes carry event_id and are gated by
-- is_event_member(event_id), exactly like comments/items. A non-member is
-- not a member, so they never see an event's polls.
--
-- VOTE PRIVACY: while a poll is OPEN a member reads only their OWN vote row
-- (tallies come from a SECURITY DEFINER function so counts don't leak rows);
-- once CLOSED, all members may read every vote (who voted for what).
--
-- Idempotent enough to re-run during development.

-- ────────────────────────────────────────────────────────────────────────────
-- Enums
-- ────────────────────────────────────────────────────────────────────────────
do $$
begin
  if not exists (select 1 from pg_type where typname = 'poll_kind') then
    create type public.poll_kind as enum ('general', 'date', 'place');
  end if;
  if not exists (select 1 from pg_type where typname = 'poll_mode') then
    create type public.poll_mode as enum ('majority', 'weighted_random');
  end if;
  if not exists (select 1 from pg_type where typname = 'poll_status') then
    create type public.poll_status as enum ('open', 'closed');
  end if;
end$$;

-- 'date' means DAY; 'time' decides the hours. Added later (poll_apply_winners
-- migration), hence the separate ALTER.
alter type public.poll_kind add value if not exists 'time';

-- ────────────────────────────────────────────────────────────────────────────
-- Tables
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.polls (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  question     text not null check (char_length(question) between 1 and 200),
  kind         public.poll_kind not null default 'general',
  mode         public.poll_mode not null default 'majority',
  status       public.poll_status not null default 'open',
  created_by   uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now(),
  closed_at    timestamptz,
  -- winning_option_id references poll_options; FK added after that table exists.
  winning_option_id uuid,
  is_tie       boolean not null default false
);
create index if not exists polls_event_idx on public.polls (event_id);

create table if not exists public.poll_options (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references public.polls(id) on delete cascade,
  event_id   uuid not null references public.events(id) on delete cascade, -- for RLS
  label      text not null check (char_length(label) between 1 and 120),
  -- Typed payload so a winner can be APPLIED to the event on close:
  -- day ('date' kind) -> 'YYYY-MM-DD', 'time' -> 'HH24:MI',
  -- general/place -> null (a place option's label IS its value).
  value      text,
  position   integer not null default 0,
  created_at timestamptz not null default now()
);
alter table public.poll_options add column if not exists value text;
create index if not exists poll_options_poll_idx on public.poll_options (poll_id);

-- Now wire the winner FK on polls (set null if the option is removed).
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'polls_winning_option_fk') then
    alter table public.polls
      add constraint polls_winning_option_fk
      foreign key (winning_option_id) references public.poll_options(id) on delete set null;
  end if;
end$$;

create table if not exists public.poll_votes (
  id         uuid primary key default gen_random_uuid(),
  poll_id    uuid not null references public.polls(id) on delete cascade,
  event_id   uuid not null references public.events(id) on delete cascade, -- for RLS
  option_id  uuid not null references public.poll_options(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  -- One vote per member per OPTION: a member may back several options in the
  -- same poll, but not the same option twice (which is what makes the app's
  -- tap-to-toggle safe against a double tap). See polls_multivote.sql for the
  -- migration that widened this from (poll_id, user_id).
  unique (poll_id, user_id, option_id)
);
create index if not exists poll_votes_poll_idx on public.poll_votes (poll_id);

-- ════════════════════════════════════════════════════════════════════════════
-- HELPERS — SECURITY DEFINER, to keep policies non-recursive (same rationale as
-- is_event_member). is_poll_closed lets the votes SELECT policy reveal all rows
-- only after close without the policy reading poll_votes recursively.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.is_poll_closed(p_poll uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (select 1 from public.polls p where p.id = p_poll and p.status = 'closed');
$$;

revoke all on function public.is_poll_closed(uuid) from public;
grant execute on function public.is_poll_closed(uuid) to authenticated;

-- Tally counts for a poll, but only to members of the poll's event. Lets the
-- client show counts while a poll is open without exposing individual vote rows.
create or replace function public.poll_tallies(p_poll uuid)
returns table(option_id uuid, votes bigint)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_event uuid;
begin
  select event_id into v_event from public.polls where id = p_poll;
  if v_event is null or not public.is_event_member(v_event) then
    return;  -- not a member (or no such poll): no rows
  end if;
  return query
    select o.id, count(v.id)::bigint
    from public.poll_options o
    left join public.poll_votes v on v.option_id = o.id
    where o.poll_id = p_poll
    group by o.id;
end;
$$;

revoke all on function public.poll_tallies(uuid) from public;
grant execute on function public.poll_tallies(uuid) to authenticated;

-- Event-wide tallies: one round-trip for the whole polls tab instead of one
-- poll_tallies() call per poll. Same member gate and semantics.
create or replace function public.poll_tallies_for_event(p_event uuid)
returns table(poll_id uuid, option_id uuid, votes bigint)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not public.is_event_member(p_event) then
    return;  -- not a member: no rows
  end if;
  return query
    select o.poll_id, o.id, count(v.id)::bigint
    from public.poll_options o
    join public.polls p on p.id = o.poll_id and p.event_id = p_event
    left join public.poll_votes v on v.option_id = o.id
    group by o.poll_id, o.id;
end;
$$;
revoke all on function public.poll_tallies_for_event(uuid) from public;
grant execute on function public.poll_tallies_for_event(uuid) to authenticated;

-- Distinct voters per poll. Separate from the tallies because with multi-select
-- votes != voters, and the event page's polls preview wants voters rather than
-- a raw vote count. An RPC rather than a client-side count because the preview
-- needs one number per poll for the whole event, and a count(distinct) in the
-- database beats shipping every vote row to the phone to length-check it.
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

-- Atomic poll creation: poll + options in one call so a failure can't leave an
-- option-less poll behind. SECURITY INVOKER on purpose — the inserts run as
-- the caller, so the polls/poll_options RLS policies (member-only, date/place
-- organizer-only) still apply in full. p_values pairs 1:1 with p_labels and is
-- REQUIRED + validated for day ('date') and 'time' kinds.
drop function if exists public.create_poll_with_options(uuid, text, public.poll_kind, public.poll_mode, text[]);
create or replace function public.create_poll_with_options(
  p_event uuid, p_question text, p_kind public.poll_kind,
  p_mode public.poll_mode, p_labels text[], p_values text[] default null)
returns uuid
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_poll uuid;
  v_pos int := 0;
  v_label text;
  v_value text;
  i int;
begin
  if p_labels is null or array_length(p_labels, 1) < 2 then
    raise exception 'a poll needs at least two options' using errcode = 'check_violation';
  end if;
  if p_values is not null
     and array_length(p_values, 1) is distinct from array_length(p_labels, 1) then
    raise exception 'p_values must pair 1:1 with p_labels' using errcode = 'check_violation';
  end if;
  insert into public.polls (event_id, question, kind, mode, created_by)
  values (p_event, btrim(p_question), p_kind, p_mode, auth.uid())
  returning id into v_poll;
  for i in 1 .. array_length(p_labels, 1) loop
    v_label := btrim(coalesce(p_labels[i], ''));
    v_value := case when p_values is null then null
                    else nullif(btrim(coalesce(p_values[i], '')), '') end;
    if v_label <> '' then
      v_pos := v_pos + 1;
      if p_kind = 'date' then
        if v_value is null then
          raise exception 'a day option needs a date value' using errcode = 'check_violation';
        end if;
        begin perform v_value::date;
        exception when others then
          raise exception 'invalid date value "%"', v_value using errcode = 'check_violation';
        end;
      elsif p_kind = 'time' then
        if v_value is null then
          raise exception 'a time option needs a time value' using errcode = 'check_violation';
        end if;
        begin perform v_value::time;
        exception when others then
          raise exception 'invalid time value "%"', v_value using errcode = 'check_violation';
        end;
      end if;
      insert into public.poll_options (poll_id, event_id, label, position, value)
      values (v_poll, p_event, v_label, v_pos, v_value);
    end if;
  end loop;
  if v_pos < 2 then
    raise exception 'a poll needs at least two non-empty options' using errcode = 'check_violation';
  end if;
  return v_poll;
end;
$$;
revoke all on function public.create_poll_with_options(uuid, text, public.poll_kind, public.poll_mode, text[], text[]) from public;
grant execute on function public.create_poll_with_options(uuid, text, public.poll_kind, public.poll_mode, text[], text[]) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- GUARD — date/place polls may only be created by an organizer. (general polls:
-- any member.) Enforced in a trigger so the INSERT policy stays simple.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.reject_nonorganizer_typed_poll()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  -- 'time' included: these kinds APPLY their winner to the event on close, so
  -- creation (and hence the creator-only close) must stay organizer-gated.
  if new.kind in ('date','time','place') and not public.is_event_organizer(new.event_id) then
    raise exception 'only an organizer can create a % poll for event %', new.kind, new.event_id
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_nonorganizer_typed_poll on public.polls;
create trigger trg_reject_nonorganizer_typed_poll
  before insert on public.polls
  for each row execute function public.reject_nonorganizer_typed_poll();

-- Keep poll_options.event_id / poll_votes.event_id consistent with their poll
-- (defence so the carried-for-RLS column can't be spoofed to another event).
create or replace function public.sync_poll_child_event()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_event uuid;
begin
  select event_id into v_event from public.polls where id = new.poll_id;
  if v_event is null then
    raise exception 'poll % does not exist', new.poll_id using errcode = 'foreign_key_violation';
  end if;
  new.event_id := v_event;
  return new;
end;
$$;

drop trigger if exists trg_sync_poll_option_event on public.poll_options;
create trigger trg_sync_poll_option_event
  before insert or update of poll_id on public.poll_options
  for each row execute function public.sync_poll_child_event();

drop trigger if exists trg_sync_poll_vote_event on public.poll_votes;
create trigger trg_sync_poll_vote_event
  before insert or update of poll_id on public.poll_votes
  for each row execute function public.sync_poll_child_event();

-- Refuse votes on a closed poll (UI hides it; this is the real guard).
create or replace function public.reject_vote_on_closed_poll()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if public.is_poll_closed(new.poll_id) then
    raise exception 'poll % is closed', new.poll_id using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_vote_on_closed_poll on public.poll_votes;
create trigger trg_reject_vote_on_closed_poll
  before insert or update on public.poll_votes
  for each row execute function public.reject_vote_on_closed_poll();

-- ════════════════════════════════════════════════════════════════════════════
-- close_poll / reopen_poll — creator-only. close_poll resolves the winner ONCE
-- and stores it (majority: unique max or is_tie; weighted_random: weighted draw).
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.close_poll(p_poll uuid)
returns public.polls
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_poll      public.polls;
  v_total     bigint;
  v_maxv      bigint;
  v_winners   int;
  v_winner    uuid;
  v_tie       boolean := false;
  r           record;
  v_threshold double precision;
  v_acc       bigint := 0;
begin
  select * into v_poll from public.polls where id = p_poll;
  if v_poll.id is null then
    raise exception 'poll % not found', p_poll using errcode = 'no_data_found';
  end if;
  if v_poll.created_by <> auth.uid() then
    raise exception 'only the poll creator can close it' using errcode = 'insufficient_privilege';
  end if;
  if v_poll.status = 'closed' then
    return v_poll;  -- idempotent
  end if;

  select count(*) into v_total from public.poll_votes where poll_id = p_poll;

  if v_total = 0 then
    v_winner := null; v_tie := false;
  elsif v_poll.mode = 'majority' then
    select max(c) into v_maxv from (
      select count(*) c from public.poll_votes where poll_id = p_poll group by option_id
    ) s;
    select count(*) into v_winners from (
      select option_id, count(*) c from public.poll_votes where poll_id = p_poll
      group by option_id having count(*) = v_maxv
    ) s2;
    if v_winners = 1 then
      select option_id into v_winner from public.poll_votes where poll_id = p_poll
        group by option_id having count(*) = v_maxv;
      v_tie := false;
    else
      v_winner := null; v_tie := true;   -- tie => no winner
    end if;
  else
    -- weighted_random: pick a point in [0,total) and walk cumulative weights.
    v_threshold := random() * v_total;
    for r in
      select option_id, count(*) c from public.poll_votes where poll_id = p_poll
      group by option_id order by option_id
    loop
      v_acc := v_acc + r.c;
      if v_threshold < v_acc then
        v_winner := r.option_id;
        exit;
      end if;
    end loop;
    v_tie := false;
  end if;

  update public.polls
    set status = 'closed', closed_at = now(),
        winning_option_id = v_winner, is_tie = v_tie
  where id = p_poll
  returning * into v_poll;

  -- Apply the winner to the event (special kinds, both modes) + record the
  -- close in the history. Tie / no-votes apply nothing. The events UPDATE
  -- fires trg_log_event_changes, so the applied change lands in the History
  -- tab with the closer as actor. SECURITY DEFINER is safe: the closer is the
  -- poll's creator, and date/time/place polls are organizer-only at creation
  -- (trg_reject_nonorganizer_typed_poll).
  declare
    v_outcome text;
    v_label   text := null;
    v_value   text := null;
  begin
    if v_total = 0 then
      v_outcome := 'no_votes';
    elsif v_tie then
      v_outcome := 'tie';
    else
      v_outcome := 'winner';
      select label, value into v_label, v_value
        from public.poll_options where id = v_winner;

      if v_poll.kind = 'place' then
        update public.events set location = v_label where id = v_poll.event_id;
      elsif v_poll.kind = 'date' and v_value is not null then
        -- Replace the DATE part of starts_at, preserve time-of-day (UTC).
        update public.events
          set starts_at = ((v_value::date)::timestamp
                + coalesce((starts_at at time zone 'utc')::time, time '00:00'))
                at time zone 'utc'
          where id = v_poll.event_id;
      elsif v_poll.kind = 'time' and v_value is not null then
        -- Replace the TIME part — only when a start date already exists.
        update public.events
          set starts_at = (((starts_at at time zone 'utc')::date)::timestamp
                + v_value::time) at time zone 'utc'
          where id = v_poll.event_id and starts_at is not null;
      end if;
    end if;
    perform public.log_event_history(
      v_poll.event_id, auth.uid(), 'poll_closed', null, v_label,
      jsonb_build_object('poll_id', v_poll.id, 'question', v_poll.question,
                         'outcome', v_outcome, 'winner_label', v_label));
  end;

  return v_poll;
end;
$$;

revoke all on function public.close_poll(uuid) from public;
grant execute on function public.close_poll(uuid) to authenticated;

create or replace function public.reopen_poll(p_poll uuid)
returns public.polls
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_poll public.polls;
begin
  select * into v_poll from public.polls where id = p_poll;
  if v_poll.id is null then
    raise exception 'poll % not found', p_poll using errcode = 'no_data_found';
  end if;
  if v_poll.created_by <> auth.uid() then
    raise exception 'only the poll creator can reopen it' using errcode = 'insufficient_privilege';
  end if;
  update public.polls
    set status = 'open', closed_at = null, winning_option_id = null, is_tie = false
  where id = p_poll
  returning * into v_poll;

  perform public.log_event_history(
    v_poll.event_id, auth.uid(), 'poll_reopened', null, null,
    jsonb_build_object('poll_id', v_poll.id, 'question', v_poll.question));

  return v_poll;
end;
$$;

revoke all on function public.reopen_poll(uuid) from public;
grant execute on function public.reopen_poll(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════════════
alter table public.polls        enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes   enable row level security;

-- ── polls ── members read; a member creates their own; creator edits/deletes.
drop policy if exists polls_select on public.polls;
create policy polls_select on public.polls
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists polls_insert on public.polls;
create policy polls_insert on public.polls
  for insert to authenticated
  with check (public.is_event_member(event_id) and created_by = auth.uid());

drop policy if exists polls_update_creator on public.polls;
create policy polls_update_creator on public.polls
  for update to authenticated
  using (created_by = auth.uid()) with check (created_by = auth.uid());

drop policy if exists polls_delete_creator on public.polls;
create policy polls_delete_creator on public.polls
  for delete to authenticated
  using (created_by = auth.uid() or public.is_event_organizer(event_id));

-- ── poll_options ── members read; the poll's creator adds/removes while open.
drop policy if exists poll_options_select on public.poll_options;
create policy poll_options_select on public.poll_options
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists poll_options_insert on public.poll_options;
create policy poll_options_insert on public.poll_options
  for insert to authenticated
  with check (
    public.is_event_member(event_id)
    and exists (select 1 from public.polls p
                where p.id = poll_id and p.created_by = auth.uid() and p.status = 'open')
  );

drop policy if exists poll_options_delete on public.poll_options;
create policy poll_options_delete on public.poll_options
  for delete to authenticated
  using (exists (select 1 from public.polls p
                 where p.id = poll_id and p.created_by = auth.uid() and p.status = 'open'));

-- ── poll_votes ── insert/update/delete your OWN vote (closed-poll guard is a
-- trigger). SELECT: your own row always; everyone's rows once the poll is closed.
drop policy if exists poll_votes_insert_own on public.poll_votes;
create policy poll_votes_insert_own on public.poll_votes
  for insert to authenticated
  with check (public.is_event_member(event_id) and user_id = auth.uid());

drop policy if exists poll_votes_update_own on public.poll_votes;
create policy poll_votes_update_own on public.poll_votes
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists poll_votes_delete_own on public.poll_votes;
create policy poll_votes_delete_own on public.poll_votes
  for delete to authenticated using (user_id = auth.uid());

-- Any member of the event can see any vote in it, open or closed.
--
-- This used to be the narrower `user_id = auth.uid() or is_poll_closed(...)`
-- (ballot secrecy while open, spec rule VIS-7). VIS-7 was RETIRED by product
-- decision: members press-and-hold a poll option to see who backed it, which
-- is only possible if the rows are readable. Applied live as migration
-- `poll_votes_visible_to_all_members`; this file is the record of it.
--
-- The cardinal rule is untouched — `is_event_member(event_id)` still gates
-- everything, so a non-member reads nothing.
drop policy if exists poll_votes_select on public.poll_votes;
create policy poll_votes_select on public.poll_votes
  for select to authenticated
  using (public.is_event_member(event_id));

-- ════════════════════════════════════════════════════════════════════════════
-- Event history hook — log a poll's creation on the event's change log.
-- Lives HERE (not schema.sql) because public.polls doesn't exist when
-- schema.sql is applied to a fresh database. log_event_history() is defined in
-- schema.sql; close/reopen logging is inside the RPCs above.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.log_poll_created()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform public.log_event_history(
    new.event_id, auth.uid(), 'poll_created', null, new.question,
    jsonb_build_object('poll_id', new.id, 'question', new.question));
  return new;
end;
$$;

drop trigger if exists trg_log_poll_created on public.polls;
create trigger trg_log_poll_created
  after insert on public.polls
  for each row execute function public.log_poll_created();

-- ════════════════════════════════════════════════════════════════════════════
-- Realtime
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.polls;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.poll_options; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.poll_votes;   exception when duplicate_object then null; end;
  end if;
end$$;
