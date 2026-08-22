-- social_layer.sql — friends & friend groups (apply SECOND, after schema.sql).
--
-- TWO INVARIANTS (from CLAUDE.md):
--  1. Friends are MUTUAL, no request/accept. add_friend_by_handle writes BOTH
--     the caller's row AND the target's row in one call — the moment you add
--     someone, they see you back too. is_friend(uid) means "uid is in the
--     CALLER's address book", which (post-add) holds for both sides.
--     Removing a friend is still one-sided: only YOUR row is deleted, the
--     other person keeps you in their book unless they remove you too.
--  2. Friend groups are a SELECTION SHORTCUT, never a permission. A group is
--     never linked to an event. assign_group_to_event expands the group into
--     individual event_members rows at add-time. Changing a group later must
--     NOT retroactively expose past events — event_members stays the single
--     source of truth for visibility.

-- ────────────────────────────────────────────────────────────────────────────
-- friends — mutual address book, stored as one row per direction.
-- (owner_id) -> (friend_id) means friend_id is in owner_id's book.
-- add_friend_by_handle always writes both directions; removal only ever
-- deletes the caller's own row (see invariant 1 above).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.friends (
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  friend_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (owner_id, friend_id),
  constraint friends_no_self check (owner_id <> friend_id)
);

create index if not exists friends_friend_idx on public.friends (friend_id);

-- ────────────────────────────────────────────────────────────────────────────
-- friend_groups + members — owner-private selection groups. NEVER referenced by
-- events. Membership here is only ever read to expand into event_members.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.friend_groups (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references public.profiles(id) on delete cascade,
  name       text not null check (char_length(name) between 1 and 60),
  created_at timestamptz not null default now()
);

create index if not exists friend_groups_owner_idx on public.friend_groups (owner_id);

create table if not exists public.friend_group_members (
  group_id   uuid not null references public.friend_groups(id) on delete cascade,
  friend_id  uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (group_id, friend_id)
);

-- ════════════════════════════════════════════════════════════════════════════
-- is_friend — "is p_user in the CALLER's address book?" SECURITY DEFINER so it
-- can read friends regardless of the caller's RLS (the friends policy already
-- scopes to owner, but the definer form keeps it usable inside other policies
-- without recursion surprises).
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.is_friend(p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.friends f
    where f.owner_id = auth.uid()
      and f.friend_id = p_user
  );
$$;

revoke all on function public.is_friend(uuid) from public;
grant execute on function public.is_friend(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- add_friend_by_handle — parse 'nickname#tagline', resolve to a profile, add to
-- BOTH address books in one call (mutual, no accept step): the caller's row
-- AND the target's row are written, so the target sees the caller back
-- immediately. Returns the friend's profile id. Raises a clear error if the
-- handle is malformed or unknown, or if you try to friend yourself.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.add_friend_by_handle(p_handle text)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_hash     int;
  v_nickname text;
  v_tagline  text;
  v_friend   uuid;
  v_me       uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = 'P0001';
  end if;

  v_hash := position('#' in p_handle);
  if v_hash = 0 then
    raise exception 'handle must be in the form nickname#tagline (got %)', p_handle
      using errcode = 'invalid_parameter_value';
  end if;

  v_nickname := trim(substring(p_handle from 1 for v_hash - 1));
  v_tagline  := trim(substring(p_handle from v_hash + 1));

  select id into v_friend
  from public.profiles
  where nickname = v_nickname::citext   -- citext => case-insensitive match
    and tagline  = v_tagline::citext;

  if v_friend is null then
    raise exception 'no user with handle %', p_handle
      using errcode = 'no_data_found';
  end if;

  if v_friend = v_me then
    raise exception 'you cannot add yourself as a friend'
      using errcode = 'invalid_parameter_value';
  end if;

  -- Mutual: write both directions in one statement so the target sees the
  -- caller back immediately, no accept step.
  insert into public.friends (owner_id, friend_id)
  values (v_me, v_friend), (v_friend, v_me)
  on conflict (owner_id, friend_id) do nothing;

  return v_friend;
end;
$$;

revoke all on function public.add_friend_by_handle(text) from public;
grant execute on function public.add_friend_by_handle(text) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- assign_group_to_event — expand a friend group into individual event_members
-- rows. This is the ONLY sanctioned bridge between groups and events, and it is
-- a one-time snapshot: it copies the group's CURRENT members in. The caller
-- must own the group and be an organizer of the event. The friend
-- guard trigger still applies to each inserted row, so a group containing the
-- target simply skips that one (we swallow the trigger error per-row).
-- Returns the count of members actually added.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.assign_group_to_event(p_group uuid, p_event uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_me      uuid := auth.uid();
  v_added   int := 0;
  r         record;
begin
  if v_me is null then
    raise exception 'not authenticated' using errcode = 'P0001';
  end if;

  -- Caller must own the group.
  if not exists (select 1 from public.friend_groups g
                 where g.id = p_group and g.owner_id = v_me) then
    raise exception 'group % not found or not owned by caller', p_group
      using errcode = 'insufficient_privilege';
  end if;

  -- Caller must be an organizer of the target event.
  if not public.is_event_organizer(p_event) then
    raise exception 'must be an organizer of event % to add members', p_event
      using errcode = 'insufficient_privilege';
  end if;

  for r in
    select gm.friend_id
    from public.friend_group_members gm
    where gm.group_id = p_group
  loop
    -- Each member must still be the caller's friend (groups can outlive a
    -- friendship; we never add a non-friend). Skip silently otherwise.
    if not public.is_friend(r.friend_id) then
      continue;
    end if;
    -- No per-row exception handler any more. It existed to swallow the
    -- surprise-target guard, which is retired; with that gone a check_violation
    -- here would be a genuine bug, and aborting the batch surfaces it rather
    -- than silently dropping somebody from the event.
    insert into public.event_members (event_id, user_id, role, added_by)
    values (p_event, r.friend_id, 'member', v_me)
    on conflict (event_id, user_id) do nothing;
    if found then
      v_added := v_added + 1;
    end if;
  end loop;

  return v_added;
end;
$$;

revoke all on function public.assign_group_to_event(uuid, uuid) from public;
grant execute on function public.assign_group_to_event(uuid, uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- RLS
-- ════════════════════════════════════════════════════════════════════════════
alter table public.friends              enable row level security;
alter table public.friend_groups        enable row level security;
alter table public.friend_group_members enable row level security;

-- ── friends ── you only ever see/manage YOUR OWN address book.
drop policy if exists friends_select_own on public.friends;
create policy friends_select_own on public.friends
  for select to authenticated using (owner_id = auth.uid());

drop policy if exists friends_insert_own on public.friends;
create policy friends_insert_own on public.friends
  for insert to authenticated with check (owner_id = auth.uid());

drop policy if exists friends_delete_own on public.friends;
create policy friends_delete_own on public.friends
  for delete to authenticated using (owner_id = auth.uid());

-- ── friend_groups ── owner-private.
drop policy if exists friend_groups_all_own on public.friend_groups;
create policy friend_groups_all_own on public.friend_groups
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

-- ── friend_group_members ── visible/editable only to the group's owner.
drop policy if exists fgm_select_owner on public.friend_group_members;
create policy fgm_select_owner on public.friend_group_members
  for select to authenticated using (
    exists (select 1 from public.friend_groups g
            where g.id = group_id and g.owner_id = auth.uid())
  );

drop policy if exists fgm_insert_owner on public.friend_group_members;
create policy fgm_insert_owner on public.friend_group_members
  for insert to authenticated with check (
    exists (select 1 from public.friend_groups g
            where g.id = group_id and g.owner_id = auth.uid())
    -- may only put your own friends into your group
    and public.is_friend(friend_id)
  );

drop policy if exists fgm_delete_owner on public.friend_group_members;
create policy fgm_delete_owner on public.friend_group_members
  for delete to authenticated using (
    exists (select 1 from public.friend_groups g
            where g.id = group_id and g.owner_id = auth.uid())
  );

-- ════════════════════════════════════════════════════════════════════════════
-- ============================================================================
-- event_members INSERT -- organizer only.
--
-- This used to additionally require `is_friend(user_id)`: you could only add
-- people already in your address book. That was dropped along with the surprise
-- mechanic, so an organizer can now add anyone they can name.
--
-- IMPORTANT: this policy is NOT an exhaustive account of who can join an event.
-- assign_group_to_event and assign_crew_to_event are SECURITY DEFINER and
-- bypass it entirely, doing their own ownership/organizer checks; the
-- invite-link RPC does the same, with possession of a valid token as its
-- authorization. Read those functions too before reasoning about membership.
-- ============================================================================
drop policy if exists event_members_insert_organizer on public.event_members;
drop policy if exists event_members_insert_friend on public.event_members;
create policy event_members_insert_organizer on public.event_members
  for insert to authenticated
  with check (public.is_event_organizer(event_id));

-- Expose friends tables to realtime (RLS still applies).
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    begin alter publication supabase_realtime add table public.friends;              exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.friend_groups;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.friend_group_members; exception when duplicate_object then null; end;
  end if;
end$$;

-- NOTE: the `notifications` table (and its triggers, incl. notify_friend_added
-- on this table) lives in crews.sql, not here — notifications.crew_id
-- references public.crews(id), which doesn't exist until crews.sql is applied
-- (apply order: schema.sql -> social_layer.sql -> event_types.sql -> crews.sql).
