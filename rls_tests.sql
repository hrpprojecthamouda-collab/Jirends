-- rls_tests.sql — THE SPEC. Run in the Supabase SQL editor AFTER applying
-- schema.sql, social_layer.sql, event_types.sql.
--
-- IMPORTANT — why this is ONE big DO block:
-- The Supabase web SQL editor does not keep a single BEGIN…ROLLBACK transaction
-- across multiple top-level statements (it splits/auto-commits per statement),
-- so a classic multi-statement psql-style harness loses its fixtures and its
-- impersonation GUC between statements. Wrapping the entire spec in a single
-- `do $$ … $$` block makes it ONE statement: fixtures, impersonation
-- (set_config(...,true) is visible for the rest of the block), every assertion,
-- and teardown all share one execution context.
--
-- CLEANUP: the block does all its work, then RAISES an exception at the end
-- (carrying the verdict). Because a DO block runs in its own transaction, that
-- raise rolls back every fixture automatically — the spec leaves no residue.
-- A PASS surfaces as:  ERROR: ✅ ALL RLS TESTS PASSED
-- A FAIL surfaces as:  ERROR: ❌ ASSERTION FAILED: <which one>
-- Both are expected "errors"; only the ✅ text means success.

do $$
declare
  alice uuid := '11111111-1111-1111-1111-111111111111';
  bob   uuid := '22222222-2222-2222-2222-222222222222';
  carol uuid := '33333333-3333-3333-3333-333333333333';
  dave  uuid := '44444444-4444-4444-4444-444444444444';  -- the surprise target
  stranger uuid := '55555555-5555-5555-5555-555555555555';
  clash uuid := '99999999-9999-9999-9999-999999999999';
  ev uuid; ev_trip uuid; ev_dinner uuid; grp uuid; crew uuid; ev_crew uuid;
  n int; res uuid; ok boolean; added int;
begin
  -- Impersonation is done inline with set_config(...,true): each call sets the
  -- JWT 'sub' claim (read by auth.uid()) and the role for the rest of the block.
  -- We verified set_config(...,true) is visible within a single DO block.

  -- ════════════════════════════════════════════════════════════════════════
  -- FIXTURES — five users (+ profiles via the handle_new_user trigger).
  -- ════════════════════════════════════════════════════════════════════════
  insert into auth.users (id, email, aud, role, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (alice,'alice@test.dev','authenticated','authenticated','{}','{}',now(),now()),
    (bob,  'bob@test.dev',  'authenticated','authenticated','{}','{}',now(),now()),
    (carol,'carol@test.dev','authenticated','authenticated','{}','{}',now(),now()),
    (dave, 'dave@test.dev', 'authenticated','authenticated','{}','{}',now(),now()),
    (stranger,'stranger@test.dev','authenticated','authenticated','{}','{}',now(),now())
  on conflict (id) do nothing;

  update public.profiles set nickname='Alice',    tagline='TheCrew' where id=alice;
  update public.profiles set nickname='Bob',      tagline='TheCrew' where id=bob;
  update public.profiles set nickname='Carol',    tagline='TheCrew' where id=carol;
  update public.profiles set nickname='Dave',     tagline='TheCrew' where id=dave;
  update public.profiles set nickname='Stranger', tagline='Outside' where id=stranger;

  -- sanity: all five profiles must exist or every later test is meaningless
  select count(*) into n from public.profiles
    where id in (alice,bob,carol,dave,stranger);
  if n <> 5 then
    raise exception '❌ FIXTURE SETUP FAILED: expected 5 profiles, found % (auto-profile trigger or auth.users insert is not working)', n;
  end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 1 — handle uniqueness is case-insensitive.
  -- ════════════════════════════════════════════════════════════════════════
  insert into auth.users (id, email, aud, role, created_at, updated_at)
  values (clash,'clash@test.dev','authenticated','authenticated',now(),now())
  on conflict (id) do nothing;
  ok := false;
  begin
    update public.profiles set nickname='alice', tagline='thecrew' where id=clash;
  exception when unique_violation then ok := true;
  end;
  if not ok then raise exception '❌ ASSERTION FAILED: claiming an existing handle (any case) must be blocked'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 2 — friends are DIRECTIONAL.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('role','authenticated',true);
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);

  res := public.add_friend_by_handle('Bob#TheCrew');
  if res <> bob then raise exception '❌ ASSERTION FAILED: add_friend_by_handle should return Bob''s id'; end if;
  if not public.is_friend(bob) then raise exception '❌ ASSERTION FAILED: Alice should see Bob as friend'; end if;

  -- unknown handle / self both rejected
  ok := false;
  begin perform public.add_friend_by_handle('Nobody#Nope'); exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: friending an unknown handle must fail'; end if;
  ok := false;
  begin perform public.add_friend_by_handle('Alice#TheCrew'); exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: friending yourself must fail'; end if;

  -- directional: Bob must NOT see Alice
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  if public.is_friend(alice) then raise exception '❌ ASSERTION FAILED: friendship must be directional (Bob should NOT see Alice)'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 3 — THE CARDINAL RULE. Surprise party for Dave; Dave sees nothing.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  perform public.add_friend_by_handle('Carol#TheCrew');

  insert into public.events (title, event_type, surprise_target, created_by)
  values ('Dave''s Surprise 30th','birthday',dave,alice) returning id into ev;

  if not public.is_event_organizer(ev) then raise exception '❌ ASSERTION FAILED: creator should be organizer'; end if;
  if (select status from public.events where id=ev) <> 'idea' then
    raise exception '❌ ASSERTION FAILED: new event must auto-start at first phase (idea)'; end if;

  insert into public.event_members (event_id,user_id,added_by) values (ev,bob,alice);
  insert into public.event_members (event_id,user_id,added_by) values (ev,carol,alice);
  insert into public.comments (event_id,author_id,body) values (ev,alice,'cake at 8');
  insert into public.event_items (event_id,title,created_by) values (ev,'bring balloons',alice);
  insert into public.reactions (event_id,user_id,emoji) values (ev,alice,'🎉');

  -- Bob (member) can read it
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  select count(*) into n from public.events where id=ev;
  if n <> 1 then raise exception '❌ ASSERTION FAILED: member Bob must be able to read the event'; end if;

  -- Dave (target) can read NOTHING — event + every child
  perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
  select count(*) into n from public.events       where id=ev;        if n<>0 then raise exception '❌ CARDINAL: Dave must not read the event'; end if;
  select count(*) into n from public.comments     where event_id=ev;  if n<>0 then raise exception '❌ CARDINAL: Dave must not read comments'; end if;
  select count(*) into n from public.event_items  where event_id=ev;  if n<>0 then raise exception '❌ CARDINAL: Dave must not read items'; end if;
  select count(*) into n from public.reactions    where event_id=ev;  if n<>0 then raise exception '❌ CARDINAL: Dave must not read reactions'; end if;
  select count(*) into n from public.event_members where event_id=ev; if n<>0 then raise exception '❌ CARDINAL: Dave must not read member list'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 4 — surprise guard trigger blocks adding the target directly.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  perform public.add_friend_by_handle('Dave#TheCrew');  -- so the friend-check isn't what blocks
  ok := false;
  begin
    insert into public.event_members (event_id,user_id,added_by) values (ev,dave,alice);
  exception when others then ok := true;
  end;
  if not ok then raise exception '❌ ASSERTION FAILED: surprise guard must block adding the target as a member'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 5 — member insert requires organizer AND friend.
  -- ════════════════════════════════════════════════════════════════════════
  insert into public.events (title, event_type, created_by) values ('Weekend trip','trip',alice) returning id into ev_trip;

  -- organizer Alice cannot add the stranger (not her friend)
  ok := false;
  begin insert into public.event_members (event_id,user_id,added_by) values (ev_trip,stranger,alice);
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: organizer must not add a non-friend'; end if;

  -- Bob (not a member/organizer of ev_trip) cannot add Carol
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  ok := false;
  begin insert into public.event_members (event_id,user_id,added_by) values (ev_trip,carol,bob);
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: non-organizer must not add members'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 6 — groups are a selection shortcut; never retroactively expose.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  insert into public.friend_groups (owner_id,name) values (alice,'Inner') returning id into grp;
  insert into public.friend_group_members (group_id,friend_id) values (grp,bob);
  insert into public.events (title,event_type,created_by) values ('Group dinner','dinner',alice) returning id into ev_dinner;

  added := public.assign_group_to_event(grp,ev_dinner);   -- snapshot: Bob only
  if added <> 1 then raise exception '❌ ASSERTION FAILED: group expansion should add exactly Bob (got %)', added; end if;
  if not exists (select 1 from public.event_members where event_id=ev_dinner and user_id=bob) then
    raise exception '❌ ASSERTION FAILED: Bob should be a member after expansion'; end if;
  if exists (select 1 from public.event_members where event_id=ev_dinner and user_id=carol) then
    raise exception '❌ ASSERTION FAILED: Carol should NOT be a member (not in group at expansion time)'; end if;

  -- add Carol to the group LATER — must not touch the past event
  insert into public.friend_group_members (group_id,friend_id) values (grp,carol);
  perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
  select count(*) into n from public.events where id=ev_dinner;
  if n <> 0 then raise exception '❌ INVARIANT: adding Carol to the group later must NOT expose the past event'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 7 — status must be a phase that belongs to the event's type.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  update public.events set status='booked' where id=ev_trip;     -- valid trip phase
  if (select status from public.events where id=ev_trip) <> 'booked' then
    raise exception '❌ ASSERTION FAILED: valid phase update should be accepted'; end if;
  ok := false;
  begin update public.events set status='celebrated' where id=ev_trip;  -- birthday-only phase
  exception when foreign_key_violation then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: wrong-type status must be rejected by composite FK'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 8 — config tables are read-only to users.
  -- ════════════════════════════════════════════════════════════════════════
  select count(*) into n from public.event_type_phases;
  if n = 0 then raise exception '❌ ASSERTION FAILED: users should be able to read phase config'; end if;
  ok := false;
  begin insert into public.event_type_phases(event_type,key,label,position) values ('trip','hacked','Hacked',99);
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: users must not write phase config'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 9 — CREWS (Type 2: shared, visible groups). Distinct from friend_groups
  -- (Type 1, owner-private). Every member sees the roster; only the owner writes;
  -- and — the cardinal part — being in a crew with someone leaks NOTHING about
  -- their events. A surprise for a crew member stays invisible to that member.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  insert into public.crews (owner_id,name) values (alice,'Roommates') returning id into crew;
  insert into public.crew_members (crew_id,user_id,added_by) values (crew,bob,alice);
  insert into public.crew_members (crew_id,user_id,added_by) values (crew,dave,alice);

  -- Member Bob can read the crew AND the full roster (sees Dave) — defining Type-2 trait.
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  select count(*) into n from public.crews where id=crew;
  if n <> 1 then raise exception '❌ ASSERTION FAILED: crew member Bob must be able to read the crew'; end if;
  select count(*) into n from public.crew_members where crew_id=crew;
  if n <> 2 then raise exception '❌ ASSERTION FAILED: crew member Bob must see the full roster (expected 2, got %)', n; end if;

  -- Stranger (not a member) sees neither the crew nor its roster.
  perform set_config('request.jwt.claims', json_build_object('sub',stranger::text,'role','authenticated')::text, true);
  select count(*) into n from public.crews where id=crew;
  if n <> 0 then raise exception '❌ ASSERTION FAILED: non-member must not read the crew'; end if;
  select count(*) into n from public.crew_members where crew_id=crew;
  if n <> 0 then raise exception '❌ ASSERTION FAILED: non-member must not read the crew roster'; end if;

  -- Non-owner member Bob cannot add or remove crew members (owner-only writes).
  ok := false;
  begin insert into public.crew_members (crew_id,user_id,added_by) values (crew,carol,bob);
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: non-owner must not add crew members'; end if;

  -- CARDINAL: a surprise event for Dave, then expand the crew onto it. The
  -- per-row surprise guard must SKIP Dave, and Dave must still see nothing.
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  insert into public.events (title,event_type,surprise_target,created_by)
  values ('Daves Surprise (crew)','birthday',dave,alice) returning id into ev_crew;
  added := public.assign_crew_to_event(crew, ev_crew);   -- Bob added; Dave skipped by guard
  if added <> 1 then raise exception '❌ CARDINAL: crew expansion must add only Bob, not the target Dave (got %)', added; end if;
  if exists (select 1 from public.event_members where event_id=ev_crew and user_id=dave) then
    raise exception '❌ CARDINAL: the surprise target must NOT become an event member via crew expansion'; end if;

  -- Dave is in the crew WITH Alice, yet sees nothing of Alice''s surprise for him.
  perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
  select count(*) into n from public.events where id=ev_crew;
  if n <> 0 then raise exception '❌ CARDINAL: crew co-membership must not expose a surprise to its target'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 10 — LAST-ORGANIZER GUARD. An event must always keep ≥1 organizer, or
  -- it orphans (nobody can edit/delete it). ev_trip was created by Alice, so she
  -- is its sole organizer.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);

  -- The sole organizer cannot LEAVE (delete their own member row).
  ok := false;
  begin delete from public.event_members where event_id=ev_trip and user_id=alice;
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: the last organizer must not be able to leave (would orphan the event)'; end if;

  -- The sole organizer cannot be DEMOTED to member either.
  ok := false;
  begin update public.event_members set role='member' where event_id=ev_trip and user_id=alice;
  exception when others then ok := true; end;
  if not ok then raise exception '❌ ASSERTION FAILED: the last organizer must not be demotable (would orphan the event)'; end if;

  -- With a SECOND organizer present, the first may then leave.
  insert into public.event_members (event_id,user_id,role,added_by) values (ev_trip,bob,'organizer',alice);
  delete from public.event_members where event_id=ev_trip and user_id=alice;  -- now allowed
  if exists (select 1 from public.event_members where event_id=ev_trip and user_id=alice) then
    raise exception '❌ ASSERTION FAILED: organizer should be removable once another organizer exists'; end if;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 11 — POLLS. Members vote (one each); creator closes; vote privacy is
  -- own-only while OPEN and full after CLOSE; the surprise target sees nothing.
  -- Uses the surprise event `ev` (target=Dave; members Bob & Carol).
  -- ════════════════════════════════════════════════════════════════════════
  declare
    pmaj uuid; o1 uuid; o2 uuid; w uuid; tie boolean;
  begin
    -- Bob (a member) creates a general majority poll with two options.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    insert into public.polls (event_id,question,kind,mode,created_by)
      values (ev,'Pizza or sushi?','general','majority',bob) returning id into pmaj;
    insert into public.poll_options (poll_id,event_id,label,position) values (pmaj,ev,'Pizza',1) returning id into o1;
    insert into public.poll_options (poll_id,event_id,label,position) values (pmaj,ev,'Sushi',2) returning id into o2;

    -- Bob and Carol vote Pizza; a second vote by Bob is rejected (one per member).
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o1,bob);
    ok := false;
    begin insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o2,bob);
    exception when unique_violation then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: a member must not vote twice in a poll'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o1,carol);

    -- While OPEN, Carol can't read Bob's vote row (but can read her own).
    select count(*) into n from public.poll_votes where poll_id=pmaj and user_id=bob;
    if n <> 0 then raise exception '❌ ASSERTION FAILED: open poll must not reveal another member''s vote'; end if;

    -- CARDINAL: the surprise target (Dave) sees no poll at all.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into n from public.polls where id=pmaj;
    if n <> 0 then raise exception '❌ CARDINAL: surprise target must not see the event''s polls'; end if;

    -- Non-creator (Carol) cannot close; creator (Bob) closes -> Pizza wins (2-0).
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    ok := false; begin perform public.close_poll(pmaj); exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: only the poll creator may close it'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    perform public.close_poll(pmaj);
    select winning_option_id, is_tie into w, tie from public.polls where id=pmaj;
    if w <> o1 or tie then raise exception '❌ ASSERTION FAILED: majority winner should be Pizza, no tie'; end if;

    -- After CLOSE, Carol can now read Bob's vote (full transparency).
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    select count(*) into n from public.poll_votes where poll_id=pmaj and user_id=bob;
    if n <> 1 then raise exception '❌ ASSERTION FAILED: closed poll must reveal all votes'; end if;
  end;

  -- reset impersonation (cosmetic; the rollback below clears everything)
  perform set_config('role','postgres',true);
  perform set_config('request.jwt.claims','',true);

  -- ════════════════════════════════════════════════════════════════════════
  -- All assertions passed. Raise to (a) report success and (b) roll back the
  -- entire fixture set so the spec leaves the database untouched.
  -- ════════════════════════════════════════════════════════════════════════
  raise exception '✅ ALL RLS TESTS PASSED';
end$$;
