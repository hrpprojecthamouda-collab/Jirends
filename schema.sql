-- schema.sql — Jirends core schema (apply FIRST).
--
-- THE CARDINAL RULE: visibility == membership, enforced HERE, never in the
-- client. A user can read an event and everything hanging off it iff a row in
-- event_members links them to it. Membership is obtained by an organizer
-- adding you, or by opening an invite link.
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
  created_by      uuid not null references public.profiles(id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  constraint events_time_order check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create index if not exists events_created_by_idx      on public.events (created_by);
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
-- expenses + expense_shares — Tricount-style equal-split expense tracking.
-- Amounts are INTEGER CENTS (bigint), never float, to avoid rounding error on
-- money. No currency field (v1: plain numbers). No edit path — delete +
-- re-add is the v1 correction flow. event_settle_up() (below, with the other
-- helper functions) computes a read-only, minimum-transaction settle-up live
-- from this ledger — there is no "mark as paid".
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.expenses (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  payer_id     uuid not null references public.profiles(id) on delete cascade,
  description  text not null check (char_length(description) between 1 and 140),
  amount_cents bigint not null check (amount_cents > 0),
  created_by   uuid not null references public.profiles(id) on delete cascade,
  created_at   timestamptz not null default now()
);
create index if not exists expenses_event_idx on public.expenses (event_id);

create table if not exists public.expense_shares (
  expense_id  uuid not null references public.expenses(id) on delete cascade,
  event_id    uuid not null references public.events(id) on delete cascade, -- carried for RLS, kept in sync below
  user_id     uuid not null references public.profiles(id) on delete cascade,
  share_cents bigint not null check (share_cents >= 0),
  primary key (expense_id, user_id)
);
create index if not exists expense_shares_event_idx on public.expense_shares (event_id);
create index if not exists expense_shares_user_idx  on public.expense_shares (user_id);

-- ────────────────────────────────────────────────────────────────────────────
-- comments — top-level comments on an event, plus REPLIES that form a
-- "discussion". A reply sets parent_id to a TOP-LEVEL comment (two-level only;
-- enforced by trg_enforce_comment_two_levels). thread_title names the
-- discussion and is only valid on a root comment. (Added in the
-- comment_threads migration.)
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.comments (
  id           uuid primary key default gen_random_uuid(),
  event_id     uuid not null references public.events(id) on delete cascade,
  author_id    uuid not null references public.profiles(id) on delete cascade,
  body         text not null check (char_length(body) between 1 and 4000),
  parent_id    uuid references public.comments(id) on delete cascade,
  thread_title text check (thread_title is null or char_length(thread_title) between 1 and 120),
  created_at   timestamptz not null default now()
);

create index if not exists comments_event_idx  on public.comments (event_id);
create index if not exists comments_parent_idx on public.comments (parent_id);

-- Two-level guard + reply-count RPC live with the other comment logic below.

-- ────────────────────────────────────────────────────────────────────────────
-- reactions — carry event_id explicitly for RLS scoping (per the cardinal rule).
-- A user holds at most ONE reaction per target: choosing another emoji replaces
-- it, choosing the current one clears it. Reactions target either a comment or
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

-- ONE reaction per user per target (emoji deliberately NOT in the key — that is
-- what makes the reaction exclusive). Two partial indexes because NULL
-- comment_id (reaction-on-event) must still be deduped.
--
-- MIGRATING an existing database: these indexes replace the older
-- (…, user_id, emoji) ones, which allowed a user several emojis on one target.
-- Drop the old indexes and collapse any duplicates FIRST, or the create fails:
--
--   drop index if exists public.reactions_unique_on_comment;
--   drop index if exists public.reactions_unique_on_event;
--   delete from public.reactions r using public.reactions keep
--    where r.user_id = keep.user_id
--      and r.event_id = keep.event_id
--      and r.comment_id is not distinct from keep.comment_id
--      and (keep.created_at, keep.id) > (r.created_at, r.id);
--   -- then create the two indexes below (keeps each user's most recent)
create unique index if not exists reactions_unique_on_comment
  on public.reactions (comment_id, user_id) where comment_id is not null;
create unique index if not exists reactions_unique_on_event
  on public.reactions (event_id, user_id) where comment_id is null;
create index if not exists reactions_event_idx on public.reactions (event_id);

-- REQUIRED for un-reacting to show up live. Realtime only ships the columns in
-- a table's replica identity; with the default (primary key only) a DELETE
-- payload has no event_id, so the client's `.stream().eq('event_id', …)` filter
-- can't match it and the delete is dropped — the emoji stays on screen and
-- counts only ever grow. FULL puts every column in the payload.
alter table public.reactions replica identity full;

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

-- ────────────────────────────────────────────────────────────────────────────
-- event_history — append-only change log per event (title/description/status/
-- location/time edits + poll lifecycle). Written ONLY by SECURITY DEFINER code
-- (trg_log_event_changes, trg_log_poll_created, and the close/reopen poll RPCs)
-- via log_event_history(); there is no client write policy, so it is tamper-
-- proof. RLS scopes reads to members → a non-member sees no history.
-- (Added in the event_history migration.)
-- ────────────────────────────────────────────────────────────────────────────
create table if not exists public.event_history (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events(id) on delete cascade,
  actor_id   uuid references public.profiles(id) on delete set null,
  kind       text not null,   -- title|description|status|location|starts_at|
                              -- ends_at|poll_created|poll_closed|poll_reopened
  old_value  text,
  new_value  text,
  detail     jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists event_history_event_idx
  on public.event_history (event_id, created_at desc);

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
-- TIME CONFLICT DETECTION. Pure read-side computation over events/
-- event_members — no new table, no write path. Safety lives entirely in what
-- each function chooses to RETURN:
--   has_time_conflict / event_member_conflicts -> BOOLEAN ONLY, never an
--     event id/title, so a third party (organizer, fellow member) can never
--     learn WHAT or WHERE someone else is busy with — only THAT they are.
--   my_conflicting_events -> the caller's OWN event titles only (auth.uid()
--     is hardcoded, never a parameter), which is always safe: a user can
--     already read the title of any event they're a member of.
-- An event with starts_at but no ends_at occupies a default 2-HOUR block for
-- overlap purposes. Events with no starts_at at all never conflict (no time
-- to overlap).
-- ════════════════════════════════════════════════════════════════════════════

-- "Does p_user have any OTHER event that overlaps p_event's time window?"
-- SECURITY DEFINER (like is_friend/is_event_member): bypasses RLS to read
-- p_user's other event_members rows, but the boolean return carries no
-- identifying information, so the bypass leaks nothing.
create or replace function public.has_time_conflict(p_user uuid, p_event uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.events e0
    join public.event_members em on em.user_id = p_user and em.event_id <> p_event
    join public.events e1 on e1.id = em.event_id
    where e0.id = p_event
      and e0.starts_at is not null
      and e1.starts_at is not null
      and tstzrange(e0.starts_at, coalesce(e0.ends_at, e0.starts_at + interval '2 hours'))
          && tstzrange(e1.starts_at, coalesce(e1.ends_at, e1.starts_at + interval '2 hours'))
  );
$$;
revoke all on function public.has_time_conflict(uuid, uuid) from public;
grant execute on function public.has_time_conflict(uuid, uuid) to authenticated;

-- One round-trip for the whole Members tab instead of one has_time_conflict
-- call per member. Caller must already be a member of p_event (so a
-- non-member can't probe an arbitrary event's roster for conflicts).
create or replace function public.event_member_conflicts(p_event uuid)
returns table(user_id uuid, has_conflict boolean)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not public.is_event_member(p_event) then
    return;
  end if;
  return query
    select m.user_id, public.has_time_conflict(m.user_id, p_event)
    from public.event_members m
    where m.event_id = p_event;
end;
$$;
revoke all on function public.event_member_conflicts(uuid) from public;
grant execute on function public.event_member_conflicts(uuid) to authenticated;

-- "Which of MY OWN other events overlap p_event?" auth.uid() is hardcoded
-- (never a parameter) so this can never be pointed at someone else; returning
-- titles is safe because the caller is, by definition, already a member of
-- both events. SECURITY INVOKER (ordinary RLS) is enough -- is_event_member
-- guards entry, and the embedded events are the caller's own membership rows.
create or replace function public.my_conflicting_events(p_event uuid)
returns table(id uuid, title text)
language sql stable security invoker set search_path = public, pg_temp
as $$
  select e1.id, e1.title
  from public.events e0
  join public.event_members em on em.user_id = auth.uid() and em.event_id <> p_event
  join public.events e1 on e1.id = em.event_id
  where e0.id = p_event
    and public.is_event_member(p_event)
    and e0.starts_at is not null
    and e1.starts_at is not null
    and tstzrange(e0.starts_at, coalesce(e0.ends_at, e0.starts_at + interval '2 hours'))
        && tstzrange(e1.starts_at, coalesce(e1.ends_at, e1.starts_at + interval '2 hours'));
$$;
revoke all on function public.my_conflicting_events(uuid) from public;
grant execute on function public.my_conflicting_events(uuid) to authenticated;


-- ════════════════════════════════════════════════════════════════════════════
-- CREATOR AUTO-MEMBERSHIP — when an event is created, the creator becomes its
-- organizer. (Runs as DEFINER so it can write the row before any policy applies;
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
-- LAST-ORGANIZER GUARD — an event must always keep at least one organizer, or
-- it becomes an orphan: nobody can edit/delete it (those policies require
-- is_event_organizer). Refuse to remove (DELETE) or demote (UPDATE role away
-- from 'organizer') the event's only remaining organizer.
--
-- Skips when the parent event is already gone (cascade delete of the event
-- removes its members; that's legitimate, not an orphaning).
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.reject_last_organizer_removal()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_other_organizers int;
begin
  -- Only relevant if the OLD row was an organizer.
  if old.role <> 'organizer' then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  -- On UPDATE, if the row stays an organizer there's nothing to guard.
  if tg_op = 'UPDATE' and new.role = 'organizer' then
    return new;
  end if;

  -- If the event itself is gone (cascade), allow the row to go with it.
  if not exists (select 1 from public.events e where e.id = old.event_id) then
    return case when tg_op = 'DELETE' then old else new end;
  end if;

  select count(*) into v_other_organizers
  from public.event_members m
  where m.event_id = old.event_id
    and m.role = 'organizer'
    and m.user_id <> old.user_id;

  if v_other_organizers = 0 then
    raise exception
      'cannot remove or demote the last organizer of event % (an event must keep at least one organizer)',
      old.event_id
      using errcode = 'check_violation';
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

drop trigger if exists trg_reject_last_organizer on public.event_members;
create trigger trg_reject_last_organizer
  before delete or update of role on public.event_members
  for each row execute function public.reject_last_organizer_removal();

-- ════════════════════════════════════════════════════════════════════════════
-- COMMENT DISCUSSIONS — two-level reply guard + member-visible reply counts.
-- A reply (parent_id not null) must point at a TOP-LEVEL comment in the same
-- event; you cannot reply to a reply, and only a root comment may carry a
-- thread_title.
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.enforce_comment_two_levels()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_parent_event uuid;
  v_parent_parent uuid;
begin
  if new.parent_id is not null then
    select event_id, parent_id into v_parent_event, v_parent_parent
      from public.comments where id = new.parent_id;
    if v_parent_event is null then
      raise exception 'parent comment % does not exist', new.parent_id
        using errcode = 'foreign_key_violation';
    end if;
    if v_parent_event <> new.event_id then
      raise exception 'reply event_id must match its parent''s event'
        using errcode = 'check_violation';
    end if;
    if v_parent_parent is not null then
      raise exception 'replies are two-level only (cannot reply to a reply)'
        using errcode = 'check_violation';
    end if;
    if new.thread_title is not null then
      raise exception 'only a top-level comment may have a thread_title'
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_comment_two_levels on public.comments;
create trigger trg_enforce_comment_two_levels
  before insert or update of parent_id, thread_title on public.comments
  for each row execute function public.enforce_comment_two_levels();

-- Column guard for comment updates. The comments_update RLS policy is
-- member-scoped so any member can collaboratively name a discussion
-- (thread_title) — but RLS alone would let a member rewrite anyone's body,
-- re-attribute a comment (author_id), or move it between events (event_id).
-- This trigger freezes everything except thread_title (any member) and body
-- (author only). Freezing parent_id also closes the re-parent/self-parent
-- loophole on UPDATE.
create or replace function public.guard_comment_update()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.event_id   is distinct from old.event_id
  or new.author_id  is distinct from old.author_id
  or new.parent_id  is distinct from old.parent_id
  or new.created_at is distinct from old.created_at then
    raise exception 'comment identity columns are immutable'
      using errcode = 'check_violation';
  end if;
  if new.body is distinct from old.body and auth.uid() <> old.author_id then
    raise exception 'only the author may edit a comment''s body'
      using errcode = 'insufficient_privilege';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_guard_comment_update on public.comments;
create trigger trg_guard_comment_update
  before update on public.comments
  for each row execute function public.guard_comment_update();

-- Reply counts per root comment for an event (member-scoped, so the comment
-- list shows "N replies" without reading every reply row).
create or replace function public.comment_reply_counts(p_event uuid)
returns table(parent_id uuid, n bigint)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if not public.is_event_member(p_event) then
    return;
  end if;
  return query
    select c.parent_id, count(*)::bigint
    from public.comments c
    where c.event_id = p_event and c.parent_id is not null
    group by c.parent_id;
end;
$$;
revoke all on function public.comment_reply_counts(uuid) from public;
grant execute on function public.comment_reply_counts(uuid) to authenticated;

-- ════════════════════════════════════════════════════════════════════════════
-- EVENT HISTORY — append-only change log. log_event_history() is the single
-- writer (SECURITY DEFINER, bypasses the write-less RLS). A trigger on events
-- (below) logs watched-field edits. The pieces that depend on LATER files live
-- with their dependencies so this file still bootstraps a fresh database:
--   status_label()            -> event_types.sql (needs event_type_phases)
--   trg_log_poll_created      -> polls.sql       (needs public.polls)
--   poll_closed/poll_reopened -> polls.sql RPCs
-- ════════════════════════════════════════════════════════════════════════════
create or replace function public.log_event_history(
  p_event uuid, p_actor uuid, p_kind text,
  p_old text, p_new text, p_detail jsonb default '{}'::jsonb)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  insert into public.event_history (event_id, actor_id, kind, old_value, new_value, detail)
  values (p_event, p_actor, p_kind, p_old, p_new, coalesce(p_detail, '{}'::jsonb));
end;
$$;

-- One history row per watched field that actually changed (updated_at-only or
-- churn on untracked columns logs nothing).
create or replace function public.log_event_changes()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare a uuid := auth.uid();
begin
  if new.title is distinct from old.title then
    perform public.log_event_history(new.id, a, 'title', old.title, new.title);
  end if;
  if new.description is distinct from old.description then
    perform public.log_event_history(new.id, a, 'description', old.description, new.description);
  end if;
  if new.location is distinct from old.location then
    perform public.log_event_history(new.id, a, 'location', old.location, new.location);
  end if;
  if new.status is distinct from old.status then
    perform public.log_event_history(new.id, a, 'status',
      public.status_label(old.event_type, old.status),
      public.status_label(new.event_type, new.status));
  end if;
  if new.starts_at is distinct from old.starts_at then
    perform public.log_event_history(new.id, a, 'starts_at',
      to_char(old.starts_at, 'YYYY-MM-DD"T"HH24:MI:SSOF'),
      to_char(new.starts_at, 'YYYY-MM-DD"T"HH24:MI:SSOF'));
  end if;
  if new.ends_at is distinct from old.ends_at then
    perform public.log_event_history(new.id, a, 'ends_at',
      to_char(old.ends_at, 'YYYY-MM-DD"T"HH24:MI:SSOF'),
      to_char(new.ends_at, 'YYYY-MM-DD"T"HH24:MI:SSOF'));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_log_event_changes on public.events;
create trigger trg_log_event_changes
  after update on public.events
  for each row execute function public.log_event_changes();

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
alter table public.event_history enable row level security;

-- ── profiles ────────────────────────────────────────────────────────────────
-- Profiles are readable by any authenticated user (you must be able to look up
-- a handle to add a friend, and to render members' names). A profile carries no
-- event data, so this leaks nothing about events. You may only write your own.
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
-- THE core policy, and the one everything else leans on. You see an event iff
-- you are a member -- OR you are its creator. The creator clause is required so
-- that `INSERT ... RETURNING` works: the creator's organizer membership is added
-- by an AFTER-INSERT trigger, which is not yet visible when RETURNING evaluates
-- this SELECT check. A non-member has no member row and no creator match, so
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

-- ── expenses / expense_shares ────────────────────────────────────────────────
-- Keep expense_shares.event_id consistent with its expense (same defensive
-- shape as sync_poll_child_event in polls.sql) — the carried-for-RLS column
-- can't be spoofed to another event.
create or replace function public.sync_expense_share_event()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_event uuid;
begin
  select event_id into v_event from public.expenses where id = new.expense_id;
  if v_event is null then
    raise exception 'expense % does not exist', new.expense_id using errcode = 'foreign_key_violation';
  end if;
  new.event_id := v_event;
  return new;
end;
$$;

drop trigger if exists trg_sync_expense_share_event on public.expense_shares;
create trigger trg_sync_expense_share_event
  before insert or update of expense_id on public.expense_shares
  for each row execute function public.sync_expense_share_event();

-- Guard: payer_id must be an event member at insert time (mirrors the
-- reject_nonorganizer_typed_poll defensive trigger shape).
create or replace function public.reject_nonmember_payer()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.event_members where event_id = new.event_id and user_id = new.payer_id
  ) then
    raise exception 'payer must be a member of the event' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_nonmember_payer on public.expenses;
create trigger trg_reject_nonmember_payer
  before insert or update of payer_id, event_id on public.expenses
  for each row execute function public.reject_nonmember_payer();

-- Guard: every expense_shares.user_id must be an event member. AFTER, not
-- BEFORE: event_id is only finalised by trg_sync_expense_share_event (a
-- BEFORE trigger on this same table); AFTER guarantees it has already run.
create or replace function public.reject_nonmember_share()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.event_members where event_id = new.event_id and user_id = new.user_id
  ) then
    raise exception 'a share must belong to an event member' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_reject_nonmember_share on public.expense_shares;
create trigger trg_reject_nonmember_share
  after insert or update of user_id, event_id on public.expense_shares
  for each row execute function public.reject_nonmember_share();

alter table public.expenses       enable row level security;
alter table public.expense_shares enable row level security;

drop policy if exists expenses_select on public.expenses;
create policy expenses_select on public.expenses
  for select to authenticated using (public.is_event_member(event_id));

-- add_expense() (below) inserts through THIS policy as the authenticated
-- caller — it exists for atomicity/server-side split math, not to bypass RLS.
drop policy if exists expenses_insert on public.expenses;
create policy expenses_insert on public.expenses
  for insert to authenticated
  with check (public.is_event_member(event_id) and created_by = auth.uid());

drop policy if exists expenses_delete on public.expenses;
create policy expenses_delete on public.expenses
  for delete to authenticated
  using (created_by = auth.uid() or public.is_event_organizer(event_id));
-- No UPDATE policy: v1 has no edit path (delete + re-add).

drop policy if exists expense_shares_select on public.expense_shares;
create policy expense_shares_select on public.expense_shares
  for select to authenticated using (public.is_event_member(event_id));

-- Members may insert shares ONLY for an expense they just created (so
-- add_expense's two inserts both pass RLS as the authenticated caller).
-- There's no UPDATE/DELETE policy (shares are immutable; deleting the expense
-- cascades them).
drop policy if exists expense_shares_insert on public.expense_shares;
create policy expense_shares_insert on public.expense_shares
  for insert to authenticated
  with check (
    public.is_event_member(event_id)
    and exists (select 1 from public.expenses e where e.id = expense_id and e.created_by = auth.uid())
  );

-- Atomic expense + equal-split shares. SECURITY INVOKER: both inserts run as
-- the caller, so the policies above fully apply — this function exists for
-- atomicity (one failure can't leave a half-written expense) and to compute
-- the per-share split server-side, not to bypass RLS. Remainder from an
-- uneven split lands on the LAST participant so shares always sum exactly to
-- amount_cents.
create or replace function public.add_expense(
  p_event uuid, p_payer uuid, p_description text, p_amount_cents bigint,
  p_participant_ids uuid[])
returns uuid
language plpgsql security invoker set search_path = public, pg_temp
as $$
declare
  v_expense uuid;
  v_n int;
  v_base bigint;
  v_remainder bigint;
  v_uid uuid;
  v_i int := 0;
begin
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'amount must be positive' using errcode = 'check_violation';
  end if;
  v_n := coalesce(array_length(p_participant_ids, 1), 0);
  if v_n = 0 then
    raise exception 'an expense needs at least one participant' using errcode = 'check_violation';
  end if;

  insert into public.expenses (event_id, payer_id, description, amount_cents, created_by)
  values (p_event, p_payer, btrim(p_description), p_amount_cents, auth.uid())
  returning id into v_expense;

  v_base := p_amount_cents / v_n;
  v_remainder := p_amount_cents - (v_base * v_n);

  foreach v_uid in array p_participant_ids loop
    v_i := v_i + 1;
    insert into public.expense_shares (expense_id, event_id, user_id, share_cents)
    values (
      v_expense, p_event, v_uid,
      v_base + case when v_i = v_n then v_remainder else 0 end
    );
  end loop;

  return v_expense;
end;
$$;
revoke all on function public.add_expense(uuid, uuid, text, bigint, uuid[]) from public;
grant execute on function public.add_expense(uuid, uuid, text, bigint, uuid[]) to authenticated;

-- Minimum-transaction settle-up: net every member's balance (paid - owed),
-- then greedily pair the largest creditor with the largest debtor until both
-- (or one) reach zero, repeating until everyone is settled. O(member count)
-- — trivial even for large events. Gated by is_event_member like
-- event_member_conflicts; returns only transfers among this event's members,
-- nothing beyond what's already derivable from expenses the caller can read.
-- Read-only: there is no "mark as paid" — this is always recomputed live.
create or replace function public.event_settle_up(p_event uuid)
returns table(from_user uuid, to_user uuid, amount_cents bigint)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  r record;
  v_balances uuid[] := array[]::uuid[];
  v_amounts  bigint[] := array[]::bigint[];
  v_i int;
  v_max_credit bigint; v_max_credit_idx int;
  v_max_debit  bigint; v_max_debit_idx  int;
  v_transfer   bigint;
begin
  if not public.is_event_member(p_event) then
    return;
  end if;

  for r in
    select m.user_id,
      coalesce((select sum(e.amount_cents) from public.expenses e where e.event_id = p_event and e.payer_id = m.user_id), 0)
      - coalesce((select sum(s.share_cents) from public.expense_shares s where s.event_id = p_event and s.user_id = m.user_id), 0)
        as balance
    from public.event_members m
    where m.event_id = p_event
  loop
    if r.balance <> 0 then
      v_balances := v_balances || r.user_id;
      v_amounts  := v_amounts  || r.balance;
    end if;
  end loop;

  loop
    v_max_credit := 0; v_max_credit_idx := null;
    v_max_debit  := 0; v_max_debit_idx  := null;
    for v_i in 1 .. coalesce(array_length(v_amounts,1),0) loop
      if v_amounts[v_i] > v_max_credit then v_max_credit := v_amounts[v_i]; v_max_credit_idx := v_i; end if;
      if v_amounts[v_i] < -v_max_debit then v_max_debit := -v_amounts[v_i]; v_max_debit_idx := v_i; end if;
    end loop;
    exit when v_max_credit_idx is null or v_max_debit_idx is null or v_max_credit = 0 or v_max_debit = 0;

    v_transfer := least(v_max_credit, v_max_debit);
    from_user := v_balances[v_max_debit_idx];
    to_user   := v_balances[v_max_credit_idx];
    amount_cents := v_transfer;
    return next;

    v_amounts[v_max_credit_idx] := v_amounts[v_max_credit_idx] - v_transfer;
    v_amounts[v_max_debit_idx]  := v_amounts[v_max_debit_idx]  + v_transfer;
  end loop;
  return;
end;
$$;
revoke all on function public.event_settle_up(uuid) from public;
grant execute on function public.event_settle_up(uuid) to authenticated;

-- ── comments ────────────────────────────────────────────────────────────────
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
  for select to authenticated using (public.is_event_member(event_id));

drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments
  for insert to authenticated
  with check (public.is_event_member(event_id) and author_id = auth.uid());

-- Any event member may update a comment (used for collaborative discussion
-- thread_title naming; member-scoped). Replaces the old author-only policy.
drop policy if exists comments_update_own on public.comments;
drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments
  for update to authenticated
  using (public.is_event_member(event_id))
  with check (public.is_event_member(event_id));

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

-- ── event_history ───────────────────────────────────────────────────────────
-- Members READ the change log. No insert/update/delete policy exists by design,
-- so clients can't write or tamper with it — only the SECURITY DEFINER
-- log_event_history() (called by triggers + the poll RPCs) writes rows.
drop policy if exists event_history_select on public.event_history;
create policy event_history_select on public.event_history
  for select to authenticated
  using (public.is_event_member(event_id));

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
    begin alter publication supabase_realtime add table public.expenses;       exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.expense_shares; exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.comments;      exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.reactions;     exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.attachments;   exception when duplicate_object then null; end;
    begin alter publication supabase_realtime add table public.event_history; exception when duplicate_object then null; end;
  end if;
end$$;
