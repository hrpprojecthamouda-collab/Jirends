-- rls_tests.sql — THE SPEC. Run in the Supabase SQL editor AFTER applying
-- schema.sql, social_layer.sql, event_types.sql. Every assertion must pass.
--
-- It runs inside a single transaction that is ROLLED BACK at the end, so it
-- creates and destroys its own fixtures and leaves your data untouched.
--
-- How impersonation works: Supabase's auth.uid() reads
-- current_setting('request.jwt.claims')::json->>'sub'. We simulate a logged-in
-- user by setting that claim and switching to the `authenticated` role with
-- `set local`, exactly as PostgREST does per request. as_user()/as_anon() below
-- wrap that. Helper SECURITY DEFINER functions still run as owner, as in prod.
--
-- Assertions use a tiny `expect`/`expect_throws` pair that RAISE EXCEPTION on
-- failure, aborting the run with a clear message. A clean run prints
-- "ALL RLS TESTS PASSED".

begin;

set local client_min_messages = warning;

-- ── test scaffolding ────────────────────────────────────────────────────────
create or replace function pg_temp.as_user(p uuid) returns void
language plpgsql as $$
begin
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', p::text, 'role','authenticated')::text, true);
end$$;

create or replace function pg_temp.as_anon() returns void
language plpgsql as $$
begin
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', json_build_object('role','anon')::text, true);
end$$;

create or replace function pg_temp.reset_role() returns void
language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end$$;

create or replace function pg_temp.expect(cond boolean, msg text) returns void
language plpgsql as $$
begin
  if cond is distinct from true then
    raise exception 'ASSERTION FAILED: %', msg;
  end if;
end$$;

-- run `sql` as `who`; expect it to RAISE (i.e. be blocked / invalid).
create or replace function pg_temp.expect_blocked(who uuid, sql text, msg text) returns void
language plpgsql as $$
declare ok boolean := false;
begin
  perform pg_temp.as_user(who);
  begin
    execute sql;
  exception when others then
    ok := true;            -- good: it was blocked
  end;
  perform pg_temp.reset_role();
  if not ok then
    raise exception 'ASSERTION FAILED (expected block): %', msg;
  end if;
end$$;

-- count rows visible to `who` from `sql` (a scalar-count query).
create or replace function pg_temp.count_as(who uuid, sql text) returns integer
language plpgsql as $$
declare n integer;
begin
  perform pg_temp.as_user(who);
  execute sql into n;
  perform pg_temp.reset_role();
  return n;
end$$;

-- ── fixtures: four users ─────────────────────────────────────────────────────
-- We insert directly into auth.users (as postgres) which fires handle_new_user
-- to create profile rows; then we set handles.
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  carol uuid := '33333333-3333-3333-3333-333333333333';
  dave  uuid := '44444444-4444-4444-4444-444444444444';  -- the surprise target
begin
  insert into auth.users (id, email, aud, role, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (alice,'alice@test.dev','authenticated','authenticated','{}','{}',now(),now()),
    (bob,  'bob@test.dev',  'authenticated','authenticated','{}','{}',now(),now()),
    (carol,'carol@test.dev','authenticated','authenticated','{}','{}',now(),now()),
    (dave, 'dave@test.dev', 'authenticated','authenticated','{}','{}',now(),now())
  on conflict (id) do nothing;

  update public.profiles set nickname='Alice', tagline='TheCrew' where id=alice;
  update public.profiles set nickname='Bob',   tagline='TheCrew' where id=bob;
  update public.profiles set nickname='Carol', tagline='TheCrew' where id=carol;
  update public.profiles set nickname='Dave',  tagline='TheCrew' where id=dave;
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 1 — handle uniqueness is case-insensitive.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare collided boolean := false;
begin
  -- A different user trying to claim 'alice#thecrew' (note the different case)
  -- must be rejected by the case-insensitive unique handle index.
  insert into auth.users (id, email, aud, role, created_at, updated_at)
  values ('99999999-9999-9999-9999-999999999999','clash@test.dev','authenticated','authenticated',now(),now())
  on conflict (id) do nothing;
  begin
    update public.profiles
      set nickname='alice', tagline='thecrew'
      where id='99999999-9999-9999-9999-999999999999';
  exception when unique_violation then
    collided := true;
  end;
  perform pg_temp.expect(collided, 'claiming an existing handle (any case) is blocked by the unique index');
  raise notice 'TEST 1 (case-insensitive handle uniqueness) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 2 — friends are DIRECTIONAL. Alice adds Bob; is_friend is asymmetric.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  res   uuid;
begin
  perform pg_temp.as_user(alice);
  res := public.add_friend_by_handle('Bob#TheCrew');   -- case/handle parse
  perform pg_temp.expect(res = bob, 'add_friend_by_handle returns Bob''s id');
  -- is_friend(bob) is true for Alice...
  perform pg_temp.expect(public.is_friend(bob), 'Alice sees Bob as friend');
  perform pg_temp.reset_role();

  -- ...but NOT for Bob (he never added Alice). Directional.
  perform pg_temp.as_user(bob);
  perform pg_temp.expect(not public.is_friend(alice), 'Bob does NOT see Alice as friend (directional)');
  perform pg_temp.reset_role();

  raise notice 'TEST 2 (directional friends) ok';
end$$;

-- adding a non-existent handle, or yourself, must fail
select pg_temp.expect_blocked('11111111-1111-1111-1111-111111111111',
  $q$ select public.add_friend_by_handle('Nobody#Nope') $q$,
  'friending an unknown handle is rejected');
select pg_temp.expect_blocked('11111111-1111-1111-1111-111111111111',
  $q$ select public.add_friend_by_handle('Alice#TheCrew') $q$,
  'friending yourself is rejected');

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 3 — THE CARDINAL RULE. Alice makes a surprise party for Dave, with Bob
-- and Carol as members. Dave must be unable to read ANYTHING about it.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  carol uuid := '33333333-3333-3333-3333-333333333333';
  dave  uuid := '44444444-4444-4444-4444-444444444444';
  ev    uuid;
begin
  -- Alice needs Bob and Carol as friends to add them.
  perform pg_temp.as_user(alice);
  perform public.add_friend_by_handle('Carol#TheCrew');

  insert into public.events (title, event_type, surprise_target, created_by)
  values ('Dave''s Surprise 30th', 'birthday', dave, alice)
  returning id into ev;
  -- creator trigger made Alice an organizer; status auto-set to first phase.
  perform pg_temp.expect(public.is_event_organizer(ev), 'Alice is organizer of her event');

  insert into public.event_members (event_id, user_id, added_by) values (ev, bob, alice);
  insert into public.event_members (event_id, user_id, added_by) values (ev, carol, alice);

  -- A comment + item + reaction so we can prove children are hidden too.
  insert into public.comments (event_id, author_id, body) values (ev, alice, 'cake at 8');
  insert into public.event_items (event_id, title, created_by) values (ev, 'bring balloons', alice);
  insert into public.reactions (event_id, user_id, emoji) values (ev, alice, '🎉');
  perform pg_temp.reset_role();

  -- Status was auto-set to birthday's first phase ('idea').
  perform pg_temp.expect(
    (select status from public.events where id = ev) = 'idea',
    'new event auto-starts at first phase (idea)');

  -- Members CAN see it.
  perform pg_temp.expect(pg_temp.count_as(bob,
    format('select count(*) from public.events where id = %L', ev)) = 1,
    'Bob (member) can read the event');

  -- THE TARGET CANNOT — event, comments, items, reactions, members all invisible.
  perform pg_temp.expect(pg_temp.count_as(dave,
    format('select count(*) from public.events where id = %L', ev)) = 0,
    'CARDINAL: Dave (surprise target) cannot read the event');
  perform pg_temp.expect(pg_temp.count_as(dave,
    format('select count(*) from public.comments where event_id = %L', ev)) = 0,
    'CARDINAL: Dave cannot read its comments');
  perform pg_temp.expect(pg_temp.count_as(dave,
    format('select count(*) from public.event_items where event_id = %L', ev)) = 0,
    'CARDINAL: Dave cannot read its items');
  perform pg_temp.expect(pg_temp.count_as(dave,
    format('select count(*) from public.reactions where event_id = %L', ev)) = 0,
    'CARDINAL: Dave cannot read its reactions');
  perform pg_temp.expect(pg_temp.count_as(dave,
    format('select count(*) from public.event_members where event_id = %L', ev)) = 0,
    'CARDINAL: Dave cannot read its member list');

  raise notice 'TEST 3 (cardinal rule: surprise target blind) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 4 — surprise guard trigger: cannot add the target as a member, even if
-- you try directly. (Second line of defence.)
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  dave  uuid := '44444444-4444-4444-4444-444444444444';
  ev    uuid;
begin
  perform pg_temp.as_user(alice);
  -- Alice must be Dave's friend to even attempt the insert (otherwise the
  -- friend-check would be what blocks it, not the surprise guard). Add Dave.
  perform public.add_friend_by_handle('Dave#TheCrew');
  select id into ev from public.events where surprise_target = dave limit 1;
  perform pg_temp.reset_role();

  -- Direct attempt to add Dave to his own surprise must be rejected by the trigger.
  perform pg_temp.expect_blocked(alice,
    format('insert into public.event_members (event_id, user_id, added_by) values (%L,%L,%L)', ev, dave, alice),
    'surprise guard trigger blocks adding the target as a member');

  raise notice 'TEST 4 (surprise guard trigger) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 5 — member insert requires organizer AND friend. Bob (a member but NOT
-- organizer) cannot add anyone. Alice cannot add a non-friend.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  carol uuid := '33333333-3333-3333-3333-333333333333';
  ev    uuid;
  stranger uuid := '55555555-5555-5555-5555-555555555555';
begin
  -- a fresh non-surprise event by Alice
  perform pg_temp.as_user(alice);
  insert into public.events (title, event_type, created_by)
  values ('Weekend trip', 'trip', alice) returning id into ev;
  perform pg_temp.reset_role();

  -- create a stranger Alice has NOT friended
  insert into auth.users (id, email, aud, role, created_at, updated_at)
  values (stranger,'stranger@test.dev','authenticated','authenticated',now(),now())
  on conflict (id) do nothing;
  update public.profiles set nickname='Stranger', tagline='Outside' where id = stranger;

  -- Alice (organizer) cannot add the stranger (not her friend).
  perform pg_temp.expect_blocked(alice,
    format('insert into public.event_members (event_id,user_id,added_by) values (%L,%L,%L)', ev, stranger, alice),
    'organizer cannot add a non-friend');

  -- Bob is not even a member of this event, let alone an organizer: cannot add Carol.
  perform pg_temp.expect_blocked(bob,
    format('insert into public.event_members (event_id,user_id,added_by) values (%L,%L,%L)', ev, carol, bob),
    'non-organizer cannot add members');

  raise notice 'TEST 5 (member insert: organizer AND friend) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 6 — groups are a SELECTION SHORTCUT, never a permission. Expanding a
-- group adds CURRENT members as event_members; adding to the group LATER does
-- not retroactively expose the past event.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  carol uuid := '33333333-3333-3333-3333-333333333333';
  grp   uuid;
  ev    uuid;
  added int;
begin
  perform pg_temp.as_user(alice);
  -- Alice already friends Bob and Carol (tests 2/3). Build a group with Bob only.
  insert into public.friend_groups (owner_id, name) values (alice, 'Inner') returning id into grp;
  insert into public.friend_group_members (group_id, friend_id) values (grp, bob);

  insert into public.events (title, event_type, created_by)
  values ('Group dinner', 'dinner', alice) returning id into ev;

  added := public.assign_group_to_event(grp, ev);   -- snapshot: Bob only
  perform pg_temp.expect(added = 1, 'group expansion added exactly Bob');
  perform pg_temp.expect(
    exists (select 1 from public.event_members where event_id=ev and user_id=bob),
    'Bob is a member after expansion');
  perform pg_temp.expect(
    not exists (select 1 from public.event_members where event_id=ev and user_id=carol),
    'Carol is NOT a member (was not in the group at expansion time)');

  -- NOW add Carol to the group. This must NOT touch the past event.
  insert into public.friend_group_members (group_id, friend_id) values (grp, carol);
  perform pg_temp.reset_role();

  perform pg_temp.expect(pg_temp.count_as(carol,
    format('select count(*) from public.events where id=%L', ev)) = 0,
    'INVARIANT: adding Carol to the group later does NOT expose the past event');

  raise notice 'TEST 6 (groups never retroactively expose) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 7 — status must be a phase that belongs to the event's type (composite
-- FK). A trip cannot be put into 'celebrated' (a birthday-only phase).
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  ev    uuid;
begin
  perform pg_temp.as_user(alice);
  insert into public.events (title, event_type, created_by)
  values ('Phase test trip', 'trip', alice) returning id into ev;
  perform pg_temp.reset_role();

  -- a valid trip phase works
  perform pg_temp.as_user(alice);
  update public.events set status = 'booked' where id = ev;   -- valid for trip
  perform pg_temp.reset_role();
  perform pg_temp.expect((select status from public.events where id=ev)='booked',
    'valid phase transition accepted');

  -- an invalid (wrong-type) phase is rejected by the composite FK
  perform pg_temp.expect_blocked(alice,
    format('update public.events set status=''celebrated'' where id=%L', ev),
    'status from another type is rejected by composite FK');

  raise notice 'TEST 7 (status belongs to type) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
-- TEST 8 — config tables are read-only to users.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare alice uuid := '11111111-1111-1111-1111-111111111111';
begin
  perform pg_temp.expect(pg_temp.count_as(alice,
    'select count(*) from public.event_type_phases') > 0,
    'users can read phase config');
  perform pg_temp.expect_blocked(alice,
    $q$ insert into public.event_type_phases(event_type,key,label,position) values ('trip','hacked','Hacked',99) $q$,
    'users cannot write phase config');
  raise notice 'TEST 8 (config read-only) ok';
end$$;

-- ════════════════════════════════════════════════════════════════════════════
do $$ begin raise notice '────────────────────────────'; raise notice 'ALL RLS TESTS PASSED'; raise notice '────────────────────────────'; end$$;

rollback;
