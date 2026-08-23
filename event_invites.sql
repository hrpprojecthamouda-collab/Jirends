-- Invite links: join an event by opening a URL.
--
-- This is the SECOND door into event_members. The first is an organizer adding
-- you (event_members_insert_organizer). This one is a token: possession of a
-- valid, unexpired, unrevoked invite IS the authorization, which is why the
-- join RPC is SECURITY DEFINER and bypasses that policy entirely. Modelled on
-- assign_crew_to_event, which does the same thing for a different reason.
--
-- VISIBILITY: unchanged. is_event_member() is still the only oracle, and a
-- non-member still reads nothing. What a token grants is MEMBERSHIP; sight
-- follows from that, never the other way round.

-- ---------------------------------------------------------------------------
-- Table
-- ---------------------------------------------------------------------------
create table if not exists public.event_invites (
  token       text primary key,
  event_id    uuid not null references public.events(id) on delete cascade,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  expires_at  timestamptz not null default now() + interval '30 days',
  revoked_at  timestamptz,
  claim_count integer not null default 0,
  created_at  timestamptz not null default now()
);

create index if not exists event_invites_event_idx on public.event_invites (event_id);

alter table public.event_invites enable row level security;

-- DELIBERATELY NO POLICIES.
--
-- Not an oversight: with RLS enabled and no policy, every direct client
-- read/write is denied, which is exactly what we want. A readable token table
-- is a token-enumeration surface - anyone who could SELECT it could join every
-- event in the project. All access goes through the SECURITY DEFINER functions
-- below, each of which re-implements its own authorization.

-- ---------------------------------------------------------------------------
-- Mint a link. Organizers only.
-- ---------------------------------------------------------------------------
create or replace function public.create_event_invite(p_event uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_me    uuid := auth.uid();
  v_token text;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = 'P0001';
  end if;
  if not public.is_event_organizer(p_event) then
    raise exception 'must be an organizer of event % to create an invite', p_event
      using errcode = 'insufficient_privilege';
  end if;

  -- 16 random bytes -> 22 url-safe chars. 128 bits, so guessing is not the
  -- threat model; the link leaking is.
  --
  -- Schema-qualified: gen_random_bytes is pgcrypto, which lives in the
  -- `extensions` schema, and this function pins search_path to public+pg_temp.
  -- A SECURITY DEFINER function with a loose search_path is a privilege-
  -- escalation surface, so qualify the call rather than widen the path.
  v_token := translate(encode(extensions.gen_random_bytes(16), 'base64'), '+/=', '-_');

  insert into public.event_invites (token, event_id, created_by)
  values (v_token, p_event, v_me);

  return v_token;
end;
$fn$;

revoke all on function public.create_event_invite(uuid) from public;
grant execute on function public.create_event_invite(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Look before you leap: what the joiner sees BEFORE committing.
--
-- Returns the bare minimum needed to render "Join <title>?" and nothing else -
-- no description, no roster, no comments, and NOT the event id. Handing back
-- the id would let a caller try to read the event directly; RLS would refuse,
-- but there is no reason to publish the identifier at all.
--
-- Returns ZERO ROWS - never an error - for an unknown, expired or revoked
-- token, so it cannot be used to tell "no such token" apart from "token that
-- has been turned off".
-- ---------------------------------------------------------------------------
create or replace function public.peek_invite(p_token text)
returns table (
  event_title      text,
  event_starts_at  timestamptz,
  organizer_label  text,
  member_count     bigint,
  already_member   boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_event uuid;
begin
  select i.event_id into v_event
    from public.event_invites i
   where i.token = p_token
     and i.revoked_at is null
     and i.expires_at > now();

  if v_event is null then
    return;  -- no rows: unknown, expired or revoked, indistinguishably
  end if;

  return query
    select e.title,
           e.starts_at,
           coalesce(p.nickname || '#' || p.tagline, ''),
           (select count(*) from public.event_members m where m.event_id = e.id),
           exists (select 1 from public.event_members m
                    where m.event_id = e.id and m.user_id = auth.uid())
      from public.events e
      left join public.profiles p on p.id = e.created_by
     where e.id = v_event;
end;
$fn$;

revoke all on function public.peek_invite(text) from public;
grant execute on function public.peek_invite(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Redeem. Returns the event id, which the caller may now legitimately know.
-- ---------------------------------------------------------------------------
create or replace function public.join_event_with_token(p_token text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_me  uuid := auth.uid();
  v_inv public.event_invites;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = 'P0001';
  end if;

  -- Lock the row: claim_count is incremented below and two people may redeem
  -- the same link at the same moment.
  select * into v_inv
    from public.event_invites
   where token = p_token
   for update;

  if v_inv.token is null
     or v_inv.revoked_at is not null
     or v_inv.expires_at <= now() then
    raise exception 'this invite link is no longer valid'
      using errcode = 'P0001';
  end if;

  -- Already in? Succeed quietly and hand back the event. Re-opening a link you
  -- have already used should land you in the event, not show an error.
  if exists (select 1 from public.event_members
              where event_id = v_inv.event_id and user_id = v_me) then
    return v_inv.event_id;
  end if;

  insert into public.event_members (event_id, user_id, role, added_by)
  values (v_inv.event_id, v_me, 'member', v_inv.created_by);

  update public.event_invites
     set claim_count = claim_count + 1
   where token = p_token;

  return v_inv.event_id;
end;
$fn$;

revoke all on function public.join_event_with_token(text) from public;
grant execute on function public.join_event_with_token(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Turn a link off, and list an event's live links. Organizers only.
-- ---------------------------------------------------------------------------
create or replace function public.revoke_event_invite(p_token text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_event uuid;
begin
  select event_id into v_event from public.event_invites where token = p_token;
  if v_event is null then
    return;  -- nothing to revoke; say nothing about whether it ever existed
  end if;
  if not public.is_event_organizer(v_event) then
    raise exception 'must be an organizer to revoke an invite'
      using errcode = 'insufficient_privilege';
  end if;
  update public.event_invites set revoked_at = now()
   where token = p_token and revoked_at is null;
end;
$fn$;

revoke all on function public.revoke_event_invite(text) from public;
grant execute on function public.revoke_event_invite(text) to authenticated;

create or replace function public.event_invites_for_event(p_event uuid)
returns table (token text, expires_at timestamptz, claim_count integer)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
begin
  if not public.is_event_organizer(p_event) then
    return;  -- not an organizer: no rows
  end if;
  return query
    select i.token, i.expires_at, i.claim_count
      from public.event_invites i
     where i.event_id = p_event
       and i.revoked_at is null
       and i.expires_at > now()
     order by i.created_at desc;
end;
$fn$;

revoke all on function public.event_invites_for_event(uuid) from public;
grant execute on function public.event_invites_for_event(uuid) to authenticated;
