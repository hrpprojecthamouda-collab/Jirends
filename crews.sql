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
