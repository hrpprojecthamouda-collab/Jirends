-- schema.sql — Jirends core schema (apply FIRST).
--
-- THE CARDINAL RULE: visibility == membership, enforced HERE, never in the
-- client. A user can read an event and everything hanging off it iff a row in
-- event_members links them to it. The surprise target is excluded two ways:
-- they are simply not added as a member, AND a BEFORE INSERT trigger refuses to
-- add them. Do not weaken either.
--
-- Apply order: schema.sql -> social_layer.sql -> event_types.sql, then
-- rls_tests.sql to confirm the model holds.
--
-- This file is idempotent enough to re-run during development: it drops the
-- objects it owns before recreating them. It does NOT drop auth.* anything.

-- ────────────────────────────────────────────────────────────────────────────
-- Extensions
-- ────────────────────────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";          -- gen_random_uuid()
create extension if not exists "citext";             -- case-insensitive handle

-- ────────────────────────────────────────────────────────────────────────────
-- Enums owned by this file
-- ────────────────────────────────────────────────────────────────────────────
-- event_type is intentionally defined in event_types.sql (it owns the type
-- catalogue). member_role and rsvp_status are core, so they live here.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'member_role') then
    create type public.member_role as enum ('organizer', 'member');
  end if;
  if not exists (select 1 from pg_type where typname = 'rsvp_status') then
    create type public.rsvp_status as enum ('pending', 'going', 'maybe', 'declined');
  end if;
end$$;

-- ────────────────────────────────────────────────────────────────────────────
-- profiles — mirror of auth.users. nickname + tagline form the handle.
-- nickname/tagline are nullable until onboarding sets them; once set, the
-- (lower(nickname), lower(tagline)) pair is globally unique (citext handles the
-- case-insensitivity).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nickname    citext,
  tagline     citext,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- a handle is "complete" only when both parts are present
  constraint profiles_handle_both_or_neither
    check ((nickname is null) = (tagline is null)),
  constraint profiles_nickname_no_hash check (nickname is null or position('#' in nickname) = 0),
  constraint profiles_tagline_no_hash  check (tagline  is null or position('#' in tagline)  = 0),
  constraint profiles_nickname_len check (nickname is null or char_length(nickname) between 2 and 24),
  constraint profiles_tagline_len  check (tagline  is null or char_length(tagline)  between 2 and 24)
);

-- The unique handle: only enforced on rows that have completed onboarding.
create unique index if not exists profiles_handle_unique
  on public.profiles (nickname, tagline)
  where nickname is not null and tagline is not null;

-- ────────────────────────────────────────────────────────────────────────────
-- events — the ticket.
-- event_type / status columns exist here; the composite FK that validates
-- (event_type, status) against the per-type phase catalogue is added in
-- event_types.sql (which is applied after this file). status is left nullable
-- here and is populated to the type's first phase by a trigger in that file.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.events (
  id              uuid primary key default gen_random_uuid(),
  title           text not null check (char_length(title) between 1 and 140),
  description     text,
  event_type      text not null,
  status          text,
  properties      jsonb not null default '{}'::jsonb,
  starts_at       timestamptz,
  ends_at         timestamptz,
  location        text,
  surprise_target uuid references public.profiles(id) on delete set null,
  created_by      uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint events_time_order check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create index if not exists events_created_by_idx      on public.events (created_by);
create index if not exists events_surprise_target_idx on public.events (surprise_target);
create index if not exists events_type_idx            on public.events (event_type);

-- ────────────────────────────────────────────────────────────────────────────
-- event_members — membership == visibility.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.event_members (
  event_id   uuid not null references public.events(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  role       public.member_role not null default 'member',
  rsvp       public.rsvp_status not null default 'pending',
  added_by   uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

create index if not exists event_members_user_idx on public.event_members (user_id);

-- ────────────────────────────────────────────────────────────────────────────
-- event_items — assignable sub-tasks ("who brings dessert").
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.event_items (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 200),
  is_done     boolean not null default false,
  assigned_to uuid references public.profiles(id) on delete set null,
  position    integer not null default 0,
  created_by  uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists event_items_event_idx on public.event_items (event_id);

-- ────────────────────────────────────────────────────────────────────────────
-- comments
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.comments (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  author_id  uuid not null references public.profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists comments_event_idx on public.comments (event_id);

-- ────────────────────────────────────────────────────────────────────────────
-- reactions — carry event_id explicitly for RLS scoping (per the cardinal rule).
-- A user reacts once per (target, emoji). Reactions target either a comment or
-- the event itself (comment_id null => reaction on the event).
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.reactions (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  user_id    uuid not null references public.profiles(id) on delete cascade,
  emoji      text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now()
);

-- One reaction per user per emoji per target. Two partial indexes because NULL
-- comment_id (reaction-on-event) must still be deduped.
create unique index if not exists reactions_unique_on_comment
  on public.reactions (comment_id, user_id, emoji) where comment_id is not null;
create unique index if not exists reactions_unique_on_event
  on public.reactions (event_id, user_id, emoji) where comment_id is null;
create index if not exists reactions_event_idx on public.reactions (event_id);

-- ────────────────────────────────────────────────────────────────────────────
-- attachments — metadata; bytes live in Storage bucket 'event-attachments'
-- under path {event_id}/{filename}.
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.attachments (
  id          uuid primary key default gen_random_uuid(),
  event_id    uuid not null references public.events(id) on delete cascade,
  storage_path text not null,
  filename    text not null,
  mime_type   text,
  size_bytes  bigint,
  uploaded_by uuid not null references public.profiles(id) on delete cascade,
  created_at  timestamptz not null default now()
);

create index if not exists attachments_event_idx on public.attachments (event_id);

-- ════════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS — SECURITY DEFINER on purpose. They run as the table owner,
-- bypassing RLS *inside the function body*, which is exactly what stops the
-- event_members SELECT policy from recursing into itself. Never inline a
-- membership subquery into a policy; call these.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.is_event_member(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.event_members m
    where m.event_id = p_event_id
      and m.user_id  = auth.uid()
  );
$$;

create or replace function public.is_event_organizer(p_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.event_members m
    where m.event_id = p_event_id
      and m.user_id  = auth.uid()
      and m.role     = 'organizer'
  );
$$;

revoke all on function public.is_event_member(uuid)    from public;
revoke all on function public.is_event_organizer(uuid) from public;
grant execute on function public.is_event_member(uuid)    to authenticated;
grant execute on function public.is_event_organizer(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- SURPRISE GUARD — second line of defence. Refuse to insert the event's
-- surprise_target as a member. (First line: callers simply don't add them.)
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.reject_surprise_target_member()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_target uuid;
begin
  select surprise_target into v_target from public.events where id = new.event_id;
  if v_target is not null and v_target = new.user_id then
    raise exception 'cannot add the surprise target (%) as a member of event %',
      new.user_id, new.event_id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_surprise_target on public.event_members;
create trigger trg_reject_surprise_target
  before insert or update of user_id on public.event_members
  for each row execute function public.reject_surprise_target_member();

-- Also: if someone tries to set surprise_target to an existing member, refuse.
create or replace function public.reject_surprise_target_existing_member()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.surprise_target is not null and exists (
    select 1 from public.event_members m
    where m.event_id = new.id and m.user_id = new.surprise_target
  ) then
    raise exception 'cannot make existing member (%) the surprise target of event %',
      new.surprise_target, new.id
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_surprise_target_existing on public.events;
create trigger trg_reject_surprise_target_existing
  before insert or update of surprise_target on public.events
  for each row execute function public.reject_surprise_target_existing_member();

-- ════════════════════════════════════════════════════════════════════════════
-- CREATOR AUTO-MEMBERSHIP — when an event is created, the creator becomes its
-- organizer. (A creator who is also their own surprise target is nonsensical;
-- the guard above would reject it, so we skip in that impossible case.)
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.add_creator_as_organizer()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.event_members (event_id, user_id, role, rsvp, added_by)
  values (new.id, new.created_by, 'organizer', 'going', new.created_by)
  on conflict (event_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trg_add_creator_as_organizer on public.events;
create trigger trg_add_creator_as_organizer
  after insert on public.events
  for each row execute function public.add_creator_as_organizer();

-- ════════════════════════════════════════════════════════════════════════════
-- updated_at maintenance
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists trg_events_touch on public.events;
create trigger trg_events_touch before update on public.events
  for each row execute function public.touch_updated_at();

drop trigger if exists trg_profiles_touch on public.profiles;
create trigger trg_profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();

-- ════════════════════════════════════════════════════════════════════════════
-- PROFILE AUTO-CREATION — mirror new auth.users into profiles (handle null
-- until onboarding). SECURITY DEFINER so it can write the row from the auth
-- trigger context.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ════════════════════════════════════════════════════════════════════════════
alter table public.profiles      enable row level security;
alter table public.events        enable row level security;
alter table public.event_members enable row level security;
alter table public.event_items   enable row level security;
alter table public.comments      enable row level security;
alter table public.reactions     enable row level security;
alter table public.attachments   enable row level security;

-- ── profiles ────────────────────────────────────────────────────────────────
-- Profiles are readable by any authenticated user (you must be able to look up
-- a handle to add a friend, and to render members' names). A profile carries no
-- event data, so this leaks nothing about surprises. You may only write your own.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles
  for select to authenticated using (true);

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Insert is normally done by the auth trigger; allow self-insert as a fallback
-- (e.g. backfill) but never inserting someone else's row.
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert to authenticated with check (id = auth.uid());

-- ── events ──────────────────────────────────────────────────────────────────
-- THE core policy. You see an event iff you are a member — OR you are its
-- creator. The creator clause is required so that `INSERT ... RETURNING` works:
-- the creator's organizer membership is added by an AFTER-INSERT trigger, which
-- is not yet visible when RETURNING evaluates this SELECT check. It does NOT
-- weaken the cardinal rule: the surprise target is never the creator (a guard
-- trigger forbids making an existing member the target, and the creator is
-- auto-added as a member), so `created_by = auth.uid()` can never match the
-- target. The surprise target still has no member row and no creator match, so
-- this returns nothing for them.
drop policy if exists events_select_member on public.events;
create policy events_select_member on public.events
  for select to authenticated
  using (public.is_event_member(id) or created_by = auth.uid());

-- Anyone authenticated may create an event, but only as themselves.
drop policy if exists events_insert_self on public.events;
create policy events_insert_self on public.events
  for insert to authenticated with check (created_by = auth.uid());

-- Only organizers may edit/delete the event.
drop policy if exists events_update_organizer on public.events;
create policy events_update_organizer on public.events
  for update to authenticated
  using (public.is_event_organizer(id))
  with check (public.is_event_organizer(id));

drop policy if exists events_delete_organizer on public.events;
create policy events_delete_organizer on public.events
  for delete to authenticated using (public.is_event_organizer(id));

-- ── event_members ───────────────────────────────────────────────────────────
-- Members of an event can see its member list.
drop policy if exists event_members_select on public.event_members;
create policy event_members_select on public.event_members
  for select to authenticated using (public.is_event_member(event_id));

-- Inserting a member: the actor must be an organizer of the event. (The
-- friend-requirement — you may only add your own friends — is layered on in
-- social_layer.sql, which replaces this policy with the stricter one.) The
-- creator's own first organizer row is written by the SECURITY DEFINER trigger,
-- which bypasses RLS, so the bootstrap isn't blocked by this.
drop policy if exists event_members_insert_organizer on public.event_members;
create policy event_members_insert_organizer on public.event_members
  for insert to authenticated
  with check (public.is_event_organizer(event_id));

-- Updating a member row: organizers may change anyone's role/rsvp; a member may
-- update their own row (their RSVP).
drop policy if exists event_members_update on public.event_members;
create policy event_members_update on public.event_members
  for update to authenticated
  using (public.is_event_organizer(event_id) or user_id = auth.uid())
  with check (public.is_event_organizer(event_id) or user_id = auth.uid());

-- Removing a member: organizers may remove anyone; a member may remove
-- themselves (leave).
drop policy if exists event_members_delete on public.event_members;
create policy event_members_delete on public.event_members
  for delete to authenticated
  using (public.is_event_organizer(event_id) or user_id = auth.uid());

-- ── event_items ─────────────────────────────────────────────────────────────
drop policy if exists event_items_select on public.event_items;
create policy event_items_select on public.event_items
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists event_items_insert on public.event_items;
create policy event_items_insert on public.event_items
  for insert to authenticated
  with check (public.is_event_member(event_id) and created_by = auth.uid());

-- Any member may tick/untick or (re)assign items; organizers likewise. Editing
-- is intentionally open to members — claiming "I'll bring dessert" is the point.
drop policy if exists event_items_update on public.event_items;
create policy event_items_update on public.event_items
  for update to authenticated
  using (public.is_event_member(event_id))
  with check (public.is_event_member(event_id));

drop policy if exists event_items_delete on public.event_items;
create policy event_items_delete on public.event_items
  for delete to authenticated
  using (public.is_event_organizer(event_id) or created_by = auth.uid());

-- ── comments ────────────────────────────────────────────────────────────────
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments
  for insert to authenticated
  with check (public.is_event_member(event_id) and author_id = auth.uid());

drop policy if exists comments_update_own on public.comments;
create policy comments_update_own on public.comments
  for update to authenticated
  using (author_id = auth.uid()) with check (author_id = auth.uid());

drop policy if exists comments_delete on public.comments;
create policy comments_delete on public.comments
  for delete to authenticated
  using (author_id = auth.uid() or public.is_event_organizer(event_id));

-- ── reactions ───────────────────────────────────────────────────────────────
drop policy if exists reactions_select on public.reactions;
create policy reactions_select on public.reactions
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists reactions_insert on public.reactions;
create policy reactions_insert on public.reactions
  for insert to authenticated
  with check (public.is_event_member(event_id) and user_id = auth.uid());

drop policy if exists reactions_delete_own on public.reactions;
create policy reactions_delete_own on public.reactions
  for delete to authenticated using (user_id = auth.uid());

-- ── attachments ─────────────────────────────────────────────────────────────
drop policy if exists attachments_select on public.attachments;
create policy attachments_select on public.attachments
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists attachments_insert on public.attachments;
create policy attachments_insert on public.attachments
  for insert to authenticated
  with check (public.is_event_member(event_id) and uploaded_by = auth.uid());

drop policy if exists attachments_delete on public.attachments;
create policy attachments_delete on public.attachments
  for delete to authenticated
  using (uploaded_by = auth.uid() or public.is_event_organizer(event_id));

-- ════════════════════════════════════════════════════════════════════════════
-- STORAGE — event-attachments bucket, scoped by membership. The first path
-- segment is the event_id; membership of that event gates read & write.
-- ════════════════════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public)
values ('event-attachments', 'event-attachments', false)
on conflict (id) do nothing;

drop policy if exists storage_event_attachments_select on storage.objects;
create policy storage_event_attachments_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'event-attachments'
    and public.is_event_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists storage_event_attachments_insert on storage.objects;
create policy storage_event_attachments_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'event-attachments'
    and public.is_event_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists storage_event_attachments_delete on storage.objects;
create policy storage_event_attachments_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'event-attachments'
    and public.is_event_member((storage.foldername(name))[1]::uuid)
  );

-- ════════════════════════════════════════════════════════════════════════════
-- Realtime — expose the event-scoped tables so the client can stream them.
-- RLS still applies to realtime, so streams only carry rows the user may see.
-- ════════════════════════════════════════════════════════════════════════════
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    -- add tables if not already members of the publication
    begin alter publication supabase_realtime add table public.events;        exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.event_members; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.event_items;   exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.comments;      exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.reactions;     exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.attachments;   exception when duplicate_object then null; end;
  end if;
end$$;
