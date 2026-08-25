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
  dave  uuid := '44444444-4444-4444-4444-444444444444';  -- never a member of ev
  stranger uuid := '55555555-5555-5555-5555-555555555555';
  clash uuid := '99999999-9999-9999-9999-999999999999';
  ev uuid; ev_trip uuid; ev_dinner uuid; grp uuid;
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
  -- TEST 2 — friends are MUTUAL (no accept step), but REMOVAL is one-sided.
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

  -- mutual: Bob must see Alice back, with no action on Bob's part.
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  if not public.is_friend(alice) then raise exception '❌ ASSERTION FAILED: adding is mutual (Bob should see Alice back)'; end if;

  -- removal is one-sided: Alice removing Bob must not touch Bob's row for Alice.
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  delete from public.friends where owner_id = alice and friend_id = bob;
  if public.is_friend(bob) then raise exception '❌ ASSERTION FAILED: Alice removed Bob, should no longer see him'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
  if not public.is_friend(alice) then raise exception '❌ ASSERTION FAILED: removal is one-sided — Bob should still see Alice'; end if;

  -- re-add for the rest of the spec, which assumes Alice<->Bob are friends.
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  perform public.add_friend_by_handle('Bob#TheCrew');

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 3 — VISIBILITY IS MEMBERSHIP. Dave is never added; Dave sees nothing.
  -- ════════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  perform public.add_friend_by_handle('Carol#TheCrew');

  insert into public.events (title, event_type, created_by)
  values ('Alice''s birthday plan','birthday',alice) returning id into ev;

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
  -- TEST 4 — an organizer may add someone who is NOT their friend.
  -- (This slot previously asserted the surprise guard. Both that guard and
  -- the friend requirement were retired together.)
  -- ══════════════════════════════════════════════════════════════════════
  perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
  insert into public.event_members (event_id,user_id,added_by) values (ev,stranger,alice);
  if not exists (select 1 from public.event_members where event_id=ev and user_id=stranger) then
    raise exception '❌ ASSERTION FAILED: an organizer must be able to add a non-friend'; end if;
  -- Put the fixture back: later tests rely on `stranger` being outside `ev`.
  delete from public.event_members where event_id=ev and user_id=stranger;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 5 — member insert requires ORGANIZER (friendship no longer needed).
  -- ════════════════════════════════════════════════════════════════════════
  insert into public.events (title, event_type, created_by) values ('Weekend trip','trip',alice) returning id into ev_trip;

  -- Organizer Alice CAN add the stranger now: friendship is no longer a
  -- precondition for membership.
  insert into public.event_members (event_id,user_id,added_by) values (ev_trip,stranger,alice);
  if not exists (select 1 from public.event_members where event_id=ev_trip and user_id=stranger) then
    raise exception '❌ ASSERTION FAILED: organizer must be able to add a non-friend'; end if;
  delete from public.event_members where event_id=ev_trip and user_id=stranger;

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
  -- TEST 9 — RETIRED. Crews (Type 2, shared visible circles) were removed
  -- on 2026-08-23; friend_groups (TEST 6) covers what remains.
  -- ══════════════════════════════════════════════════════════════════════

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
  -- own-only while OPEN and full after CLOSE; a non-member sees nothing.
  -- Uses `ev` (members Bob & Carol; Dave is not a member).
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

    -- Bob votes Pizza AND Sushi: multi-select is allowed (polls_multivote.sql
    -- widened the unique key to (poll_id,user_id,option_id)). Backing the same
    -- option twice is still rejected, which is what makes tap-to-toggle safe.
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o1,bob);
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o2,bob);
    ok := false;
    begin insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o1,bob);
    exception when unique_violation then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: a member must not back the same option twice'; end if;
    -- Undo Bob's Sushi vote so the majority assertion below still means Pizza.
    delete from public.poll_votes where poll_id=pmaj and user_id=bob and option_id=o2;
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pmaj,ev,o1,carol);

    -- VIS-7 RETIRED: while the poll is still OPEN, Carol can already read Bob's
    -- vote. Members press-and-hold an option to see who backed it, so ballot
    -- secrecy was dropped by product decision.
    select count(*) into n from public.poll_votes where poll_id=pmaj and user_id=bob;
    if n <> 1 then raise exception '❌ ASSERTION FAILED: an open poll must show other members'' votes (VIS-7 retired)'; end if;

    -- VISIBILITY: Dave, a non-member, sees no poll at all.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into n from public.polls where id=pmaj;
    if n <> 0 then raise exception '❌ VISIBILITY: a non-member must not see the event''s polls'; end if;

    -- Non-creator (Carol) cannot close; creator (Bob) closes -> Pizza wins (2-0).
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    ok := false; begin perform public.close_poll(pmaj); exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: only the poll creator may close it'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    perform public.close_poll(pmaj);
    select winning_option_id, is_tie into w, tie from public.polls where id=pmaj;
    if w <> o1 or tie then raise exception '❌ ASSERTION FAILED: majority winner should be Pizza, no tie'; end if;

    -- After CLOSE, votes stay readable (they already were).
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    select count(*) into n from public.poll_votes where poll_id=pmaj and user_id=bob;
    if n <> 1 then raise exception '❌ ASSERTION FAILED: closed poll must reveal all votes'; end if;

    -- CARDINAL: widening votes to every MEMBER must not widen them to everyone.
    -- Dave is not a member of this event.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into n from public.poll_votes where poll_id=pmaj;
    if n <> 0 then raise exception '❌ CARDINAL: a non-member must not read poll votes'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 12 — COMMENT DISCUSSIONS. Replies (parent_id) form a two-level thread;
  -- any member may name it; a non-member sees none of it.
  -- (Uses `ev`: members Bob & Carol; Dave is not a member.)
  -- ════════════════════════════════════════════════════════════════════════
  declare
    droot uuid; drep uuid; dcnt int;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    insert into public.comments (event_id,author_id,body) values (ev,bob,'Where to eat?') returning id into droot;
    -- Carol (a different member) replies -> discussion starts.
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    insert into public.comments (event_id,author_id,body,parent_id) values (ev,carol,'Tacos',droot) returning id into drep;
    select rc.n into dcnt from public.comment_reply_counts(ev) rc where rc.parent_id = droot;
    if dcnt <> 1 then raise exception '❌ ASSERTION FAILED: reply count should be 1'; end if;

    -- Two-level: replying to a reply is rejected.
    ok := false;
    begin insert into public.comments (event_id,author_id,body,parent_id) values (ev,carol,'nested',drep);
    exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: reply-to-reply must be rejected (two-level only)'; end if;

    -- thread_title on a reply rejected; any member may title the ROOT.
    ok := false;
    begin update public.comments set thread_title='X' where id=drep; exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: thread_title on a reply must be rejected'; end if;
    update public.comments set thread_title='Dinner venue' where id=droot;  -- Carol is not the root author; still allowed
    if (select thread_title from public.comments where id=droot) <> 'Dinner venue' then
      raise exception '❌ ASSERTION FAILED: any member should be able to name the discussion'; end if;

    -- Column guard: thread_title is the ONLY member-editable column. Carol
    -- (a member, not the author) must not be able to rewrite Bob''s body,
    -- re-attribute the comment, move it to another event, or re-parent it.
    ok := false;
    begin update public.comments set body='forged' where id=droot;
    exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: a non-author must not edit a comment body'; end if;
    ok := false;
    begin update public.comments set author_id=carol where id=droot;
    exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: author_id must be immutable'; end if;
    ok := false;
    begin update public.comments set event_id=ev_trip where id=droot;
    exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: a comment must not be movable between events'; end if;
    ok := false;
    begin update public.comments set parent_id=drep where id=droot;
    exception when others then ok := true; end;
    if not ok then raise exception '❌ ASSERTION FAILED: parent_id must be immutable (no re-parenting)'; end if;
    -- The author may still edit their own body.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    update public.comments set body='Where to eat? (edited)' where id=droot;
    if (select body from public.comments where id=droot) <> 'Where to eat? (edited)' then
      raise exception '❌ ASSERTION FAILED: the author should be able to edit their own body'; end if;

    -- VISIBILITY: Dave, a non-member, sees no discussion comments or counts.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into n from public.comments where event_id=ev;
    if n <> 0 then raise exception '❌ VISIBILITY: a non-member must not read the discussion'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 13 — EVENT HISTORY. Field edits + poll lifecycle are logged by
  -- SECURITY DEFINER code; the log is read-only to members, tamper-proof, and
  -- invisible to non-members. (Uses `ev`.)
  -- ════════════════════════════════════════════════════════════════════════
  declare hn int; hold text; hnew text; hok boolean;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    -- One UPDATE touching two watched fields -> two history rows.
    update public.events set title='Dave''s Surprise (renamed)', location='Secret venue' where id=ev;
    select count(*) into hn from public.event_history where event_id=ev and kind in ('title','location');
    if hn <> 2 then raise exception '❌ TEST13: a 2-field edit should log 2 rows (got %)', hn; end if;
    select old_value, new_value into hold, hnew from public.event_history where event_id=ev and kind='location';
    if hold is not null then
      raise exception '❌ TEST13: location old_value should be null (ev was created without one), got %', hold; end if;
    if hnew <> 'Secret venue' then raise exception '❌ TEST13: location new_value wrong'; end if;
    if (select actor_id from public.event_history where event_id=ev and kind='title') <> alice then
      raise exception '❌ TEST13: actor should be Alice'; end if;

    -- A status change logs phase LABELS (status_label resolves with the enum
    -- column — this guards the function's signature staying call-compatible).
    declare hkey text; hlabel text;
    begin
      select p.key, p.label into hkey, hlabel
        from public.event_type_phases p
        join public.events e on e.id = ev and p.event_type = e.event_type
        where p.key is distinct from e.status
        order by p.position limit 1;
      update public.events set status=hkey where id=ev;
      select new_value into hnew from public.event_history where event_id=ev and kind='status';
      if hnew is distinct from hlabel then
        raise exception '❌ TEST13: status change should log the phase label % (got %)', hlabel, hnew; end if;
    end;

    -- Members read history; Dave, a non-member, reads NONE.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into hn from public.event_history where event_id=ev;
    if hn = 0 then raise exception '❌ TEST13: member should read history'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into hn from public.event_history where event_id=ev;
    if hn <> 0 then raise exception '❌ VISIBILITY: a non-member must not read history'; end if;

    -- The log is tamper-proof: a member cannot write to it directly.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    hok := false;
    begin insert into public.event_history (event_id,actor_id,kind,new_value) values (ev,bob,'title','forged');
    exception when others then hok := true; end;
    if not hok then raise exception '❌ TEST13: clients must not write event_history directly'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 14 — SPECIAL POLLS APPLY THEIR WINNER. place -> events.location;
  -- day ('date') -> the date part of starts_at (time-of-day preserved);
  -- 'time' -> the time part, ONLY when a start date exists. Organizer-gated
  -- creation includes the new 'time' kind. (Uses `ev`,
  -- organizer Alice, member Bob; plus ev_dinner for the no-date skip case.)
  -- ════════════════════════════════════════════════════════════════════════
  declare
    pp uuid; po2 uuid; tloc text; tstart timestamptz;
  begin
    -- A member (Bob) must NOT be able to create a 'time' poll (guard covers it).
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    ok := false;
    begin pp := public.create_poll_with_options(ev,'Time vote','time','majority',array['19:00','20:00'],array['19:00','20:00']);
    exception when others then ok := true; end;
    if not ok then raise exception '❌ TEST14: a non-organizer must not create a time poll'; end if;

    -- PLACE: winner becomes events.location; history logs it with the closer.
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    pp := public.create_poll_with_options(ev,'Place vote','place','majority',array['Chez Ali','Le Jardin']);
    select id into po2 from public.poll_options where poll_id=pp and position=2;
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pp,ev,po2,alice);
    perform public.close_poll(pp);
    select location into tloc from public.events where id=ev;
    if tloc is distinct from 'Le Jardin' then
      raise exception '❌ TEST14: place winner should set events.location (got %)', tloc; end if;
    if not exists (select 1 from public.event_history where event_id=ev and kind='location' and new_value='Le Jardin' and actor_id=alice) then
      raise exception '❌ TEST14: applied place must be logged in history with the closer as actor'; end if;

    -- DAY: replaces the date part of starts_at, preserves the time-of-day.
    update public.events set starts_at='2026-07-01T18:00:00Z' where id=ev;
    pp := public.create_poll_with_options(ev,'Day vote','date','majority',array['10/07','11/07'],array['2026-07-10','2026-07-11']);
    select id into po2 from public.poll_options where poll_id=pp and position=1;
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pp,ev,po2,alice);
    perform public.close_poll(pp);
    select starts_at into tstart from public.events where id=ev;
    if tstart is distinct from '2026-07-10T18:00:00Z'::timestamptz then
      raise exception '❌ TEST14: day winner should replace the date and keep 18:00Z (got %)', tstart; end if;

    -- TIME with a date present: replaces the time-of-day, keeps the date.
    pp := public.create_poll_with_options(ev,'Time vote','time','majority',array['21:15','22:00'],array['21:15','22:00']);
    select id into po2 from public.poll_options where poll_id=pp and position=1;
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pp,ev,po2,alice);
    perform public.close_poll(pp);
    select starts_at into tstart from public.events where id=ev;
    if tstart is distinct from '2026-07-10T21:15:00Z'::timestamptz then
      raise exception '❌ TEST14: time winner should set 21:15Z on the same day (got %)', tstart; end if;

    -- TIME without a date (ev_dinner has no starts_at): closes, applies NOTHING.
    pp := public.create_poll_with_options(ev_dinner,'Time vote','time','majority',array['19:00','20:30'],array['19:00','20:30']);
    select id into po2 from public.poll_options where poll_id=pp and position=1;
    insert into public.poll_votes (poll_id,event_id,option_id,user_id) values (pp,ev_dinner,po2,alice);
    perform public.close_poll(pp);
    if (select starts_at from public.events where id=ev_dinner) is not null then
      raise exception '❌ TEST14: a time winner must NOT invent a start date'; end if;

    -- Bad typed value rejected at creation.
    ok := false;
    begin pp := public.create_poll_with_options(ev,'Day vote','date','majority',array['x','y'],array['nope','2026-07-12']);
    exception when others then ok := true; end;
    if not ok then raise exception '❌ TEST14: an unparseable date value must be rejected'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 15 — NOTIFICATIONS. The first PER-RECIPIENT table: a user only ever
  -- reads their own rows. Covers friend_added (mutual fan-out)
  -- (self-add skipped), event_member_added (individual + group-expansion
  -- fan-out; creator's own auto-add skipped), event_confirmed (fires once,
  -- not on intermediate planning, not on re-advance, actor self-skipped),
  -- event_cancelled, visibility, and cross-user RLS isolation.
  -- (Reuses ev/grp/alice/bob/carol/dave from earlier tests.)
  -- ════════════════════════════════════════════════════════════════════════
  declare
    nev uuid; ncnt int; nok boolean;
  begin
    -- FRIEND_ADDED: mutual — each side reads their OWN notification. TEST 2
    -- added, removed, then re-added Alice<->Bob, so each legitimately got 2
    -- separate friend_added notifications (remove+re-add is a fresh insert,
    -- not a no-op conflict) — assert "at least 1", the mutual fan-out itself.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='friend_added' and actor_id=alice;
    if ncnt < 1 then raise exception '❌ TEST15: Bob should see >=1 friend_added from Alice (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=alice and kind='friend_added' and actor_id=bob;
    if ncnt < 1 then raise exception '❌ TEST15: Alice should see >=1 friend_added from Bob (got %)', ncnt; end if;

    -- EVENT_MEMBER_ADDED: creator's own auto-add must not self-notify; Bob's
    -- direct add to `ev` (TEST 3) must notify him exactly once.
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=alice and kind='event_member_added' and event_id=ev;
    if ncnt <> 0 then raise exception '❌ TEST15: creator auto-add must not self-notify (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='event_member_added' and event_id=ev;
    if ncnt <> 1 then raise exception '❌ TEST15: Bob should see 1 event_member_added on ev (got %)', ncnt; end if;

    -- Group-expansion fan-out on a FRESH event: exactly 1 per recipient.
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    insert into public.friend_group_members (group_id,friend_id) values (grp,carol) on conflict do nothing;
    insert into public.events (title,event_type,created_by) values ('Notif group dinner','dinner',alice) returning id into nev;
    perform public.assign_group_to_event(grp, nev);
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='event_member_added' and event_id=nev;
    if ncnt <> 1 then raise exception '❌ TEST15: Bob should have exactly 1 event_member_added from group expansion (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=carol and kind='event_member_added' and event_id=nev;
    if ncnt <> 1 then raise exception '❌ TEST15: Carol should have exactly 1 event_member_added from group expansion (got %)', ncnt; end if;

    -- VISIBILITY: Dave is not a member of `ev`, so no notification may ever
    -- be tied to it for him.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=dave and event_id = ev;
    if ncnt <> 0 then raise exception '❌ VISIBILITY (TEST15): a non-member must not be notified about an event (got %)', ncnt; end if;

    -- EVENT_CONFIRMED: idea -> planning (no notify) -> confirmed (notify
    -- non-actor members once; actor self-skipped; re-advancing doesn't refire).
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    update public.events set status='planning' where id=nev;
    update public.events set status='confirmed' where id=nev;
    select count(*) into ncnt from public.notifications where recipient_id=alice and kind='event_confirmed' and event_id=nev;
    if ncnt <> 0 then raise exception '❌ TEST15: Alice (the actor) should not self-notify on confirm (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='event_confirmed' and event_id=nev;
    if ncnt <> 1 then raise exception '❌ TEST15: Bob should have 1 event_confirmed (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    update public.events set status='done' where id=nev;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='event_confirmed' and event_id=nev;
    if ncnt <> 1 then raise exception '❌ TEST15: event_confirmed must not re-fire on a later advance (got %)', ncnt; end if;

    -- EVENT_CANCELLED.
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    update public.events set status='cancelled' where id=ev;
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=bob and kind='event_cancelled' and event_id=ev;
    if ncnt <> 1 then raise exception '❌ TEST15: Bob should see 1 event_cancelled (got %)', ncnt; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=dave and event_id=ev;
    if ncnt <> 0 then raise exception '❌ CARDINAL (TEST15): Dave must not be notified of cancellation either (got %)', ncnt; end if;

    -- RLS isolation: Bob cannot read Alice's notifications, cannot INSERT for
    -- someone else, and can only UPDATE read_at on his own rows.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ncnt from public.notifications where recipient_id=alice;
    if ncnt <> 0 then raise exception '❌ TEST15: Bob must not be able to SELECT Alice''s notifications (got %)', ncnt; end if;

    nok := false;
    begin insert into public.notifications (recipient_id, actor_id, kind) values (alice, bob, 'friend_added');
    exception when others then nok := true; end;
    if not nok then raise exception '❌ TEST15: clients must not be able to INSERT notifications directly'; end if;

    update public.notifications set read_at = now() where recipient_id=bob;
    select count(*) into ncnt from public.notifications where recipient_id=bob and read_at is null;
    if ncnt <> 0 then raise exception '❌ TEST15: read_at update should apply to all of Bob''s rows'; end if;

    nok := false;
    begin update public.notifications set kind='event_cancelled' where recipient_id=bob;
    exception when others then nok := true; end;
    if not nok then raise exception '❌ TEST15: a client must not be able to change kind via UPDATE'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 16 — TIME CONFLICT DETECTION. has_time_conflict /
  -- event_member_conflicts return a BOOLEAN ONLY (never an event id/title) so
  -- a third party can learn THAT someone is busy but never WHAT/WHERE;
  -- my_conflicting_events returns the CALLER's own event titles only
  -- (auth.uid() hardcoded, never a parameter) and is always safe. Covers
  -- overlap math, the no-ends_at 2h default, the per-event membership gate,
  -- and the cardinal case: Bob's only conflict is DAVE'S SURPRISE EVENT (`ev`,
  -- target Dave) — the boolean still shows true for Bob, but carries no event
  -- reference, so nothing about the event leaks through this channel.
  -- ════════════════════════════════════════════════════════════════════════
  declare
    cx uuid; cy uuid; cz_noend uuid; cprobe_in uuid; cprobe_out uuid;
    cconflict boolean; ccnt int; ctitle text;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);

    -- X (18:00-20:00) and Y (19:00-21:00) overlap; Bob is in both, plus `ev`
    -- (`ev` — Bob is a member; Dave is not).
    insert into public.events (title,event_type,created_by,starts_at,ends_at) values
      ('Conflict X','dinner',alice,'2026-09-01T18:00:00Z','2026-09-01T20:00:00Z') returning id into cx;
    insert into public.events (title,event_type,created_by,starts_at,ends_at) values
      ('Conflict Y','dinner',alice,'2026-09-01T19:00:00Z','2026-09-01T21:00:00Z') returning id into cy;
    insert into public.event_members (event_id,user_id,added_by) values (cx,bob,alice);
    insert into public.event_members (event_id,user_id,added_by) values (cy,bob,alice);

    select public.has_time_conflict(bob, cx) into cconflict;
    if not cconflict then raise exception '❌ TEST16: Bob should conflict on X (overlaps Y)'; end if;
    select public.has_time_conflict(bob, cy) into cconflict;
    if not cconflict then raise exception '❌ TEST16: Bob should conflict on Y (overlaps X)'; end if;
    select public.has_time_conflict(carol, cx) into cconflict;
    if cconflict then raise exception '❌ TEST16: Carol should NOT conflict (not in Y)'; end if;

    -- no-ends_at default 2h window: 10:00 (no end) occupies the implied 10-12.
    insert into public.events (title,event_type,created_by,starts_at) values
      ('NoEnd','dinner',alice,'2026-09-02T10:00:00Z') returning id into cz_noend;
    insert into public.events (title,event_type,created_by,starts_at,ends_at) values
      ('ProbeIn','dinner',alice,'2026-09-02T11:00:00Z','2026-09-02T11:30:00Z') returning id into cprobe_in;
    insert into public.events (title,event_type,created_by,starts_at,ends_at) values
      ('ProbeOut','dinner',alice,'2026-09-02T12:30:00Z','2026-09-02T13:00:00Z') returning id into cprobe_out;
    insert into public.event_members (event_id,user_id,added_by) values (cz_noend,bob,alice);
    insert into public.event_members (event_id,user_id,added_by) values (cprobe_in,bob,alice);
    insert into public.event_members (event_id,user_id,added_by) values (cprobe_out,bob,alice);

    select public.has_time_conflict(bob, cprobe_in) into cconflict;
    if not cconflict then raise exception '❌ TEST16: ProbeIn (11-11:30) should conflict with NoEnd''s implied 10-12'; end if;
    select public.has_time_conflict(bob, cprobe_out) into cconflict;
    if cconflict then raise exception '❌ TEST16: ProbeOut (12:30-13) should NOT conflict with NoEnd''s implied 10-12'; end if;

    -- event_member_conflicts: one round-trip, callable by a non-organizer
    -- member; non-members get nothing back.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ccnt from public.event_member_conflicts(cx) r where r.user_id=bob and r.has_conflict;
    if ccnt <> 1 then raise exception '❌ TEST16: event_member_conflicts should show Bob=true on X'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    select count(*) into ccnt from public.event_member_conflicts(cz_noend);
    if ccnt <> 0 then raise exception '❌ TEST16: a non-member must get an empty result from event_member_conflicts'; end if;

    -- my_conflicting_events: Bob asking about X gets back Y's title (his own
    -- data only); asking about an event he's not in returns nothing.
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ccnt from public.my_conflicting_events(cx);
    if ccnt <> 1 then raise exception '❌ TEST16: Bob should have exactly 1 conflicting event for X (got %)', ccnt; end if;
    select title into ctitle from public.my_conflicting_events(cx) limit 1;
    if ctitle <> 'Conflict Y' then raise exception '❌ TEST16: Bob''s conflict for X should be titled Conflict Y (got %)', ctitle; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',carol::text,'role','authenticated')::text, true);
    select count(*) into ccnt from public.my_conflicting_events(cy); -- Carol isn't a member of Y
    if ccnt <> 0 then raise exception '❌ TEST16: my_conflicting_events must be empty for a non-member call'; end if;

    -- Bob's membership of `ev` can make him show as conflicted to a third
    -- party, but that boolean carries no event reference — and Dave gets no
    -- boolean about Bob here at all, since he'd have to be a member of the
    -- probed event and he is not.
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    -- Structural guarantee: the function's return TYPE is boolean, full stop
    -- — it is impossible for it to carry an event id/title.
    if (select prorettype::regtype::text from pg_proc where proname='has_time_conflict') <> 'boolean' then
      raise exception '❌ CARDINAL (TEST16): has_time_conflict must return boolean only, never identify an event';
    end if;
    -- Dave cannot call event_member_conflicts for `ev` at all in a way that
    -- reveals anything since he is never event_id-listed as a member; confirm
    -- he is excluded from the result set entirely (not merely false).
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    select count(*) into ccnt from public.event_member_conflicts(ev) r where r.user_id = dave;
    if ccnt <> 0 then raise exception '❌ CARDINAL (TEST16): Dave must not appear in ev''s member-conflicts at all'; end if;
  end;

  -- ════════════════════════════════════════════════════════════════════════
  -- TEST 17 — EXPENSES. Equal-split via add_expense (atomic, remainder lands
  -- on the LAST participant so shares always sum exactly to the total);
  -- non-member payer/participant rejected; a member cannot insert
  -- expense_shares directly (must go through add_expense); only the creator
  -- or an organizer may delete (cascades shares); event_settle_up produces
  -- the minimum-transaction set and is empty once net-zero; a non-member
  -- reads nothing and gets zero settle-up rows. (Reuses `ev`, organizer
  -- Alice, members Bob & Carol; Dave is not a member. `ev_dinner` for the
  -- zero-expense case.)
  -- ════════════════════════════════════════════════════════════════════════
  declare
    xexp uuid; xsum bigint; xcnt int; xok boolean;
  begin
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);

    -- Uneven 3-way split: 100 cents / 3 -> 33,33,34 (remainder to last).
    xexp := public.add_expense(ev, alice, 'Snacks', 100, array[alice,bob,carol]);
    select sum(share_cents) into xsum from public.expense_shares where expense_id=xexp;
    if xsum <> 100 then raise exception '❌ TEST17: shares should sum to 100 (got %)', xsum; end if;
    if (select share_cents from public.expense_shares where expense_id=xexp and user_id=carol) <> 34 then
      raise exception '❌ TEST17: the remainder should land on the LAST participant'; end if;
    if (select share_cents from public.expense_shares where expense_id=xexp and user_id=alice) <> 33 then
      raise exception '❌ TEST17: the first participant should get the base share'; end if;

    -- Non-member payer / participant rejected.
    xok := false;
    begin perform public.add_expense(ev, stranger, 'Bad payer', 50, array[alice,bob]);
    exception when others then xok := true; end;
    if not xok then raise exception '❌ TEST17: a non-member payer must be rejected'; end if;
    xok := false;
    begin perform public.add_expense(ev, alice, 'Bad participant', 50, array[alice,stranger]);
    exception when others then xok := true; end;
    if not xok then raise exception '❌ TEST17: a non-member participant must be rejected'; end if;

    -- A member cannot insert expense_shares directly (bypassing add_expense).
    perform set_config('request.jwt.claims', json_build_object('sub',bob::text,'role','authenticated')::text, true);
    xok := false;
    begin insert into public.expense_shares (expense_id,event_id,user_id,share_cents) values (xexp,ev,bob,999);
    exception when others then xok := true; end;
    if not xok then raise exception '❌ TEST17: a non-creator must not insert expense_shares directly'; end if;

    -- Delete permission: RLS denial is SILENT (0 rows affected, no
    -- exception) — verify by row survival, not by expecting an error.
    delete from public.expenses where id=xexp; -- Bob: not creator, not organizer
    if not exists (select 1 from public.expenses where id=xexp) then
      raise exception '❌ TEST17: a non-creator/non-organizer DELETE must affect 0 rows'; end if;
    perform set_config('request.jwt.claims', json_build_object('sub',alice::text,'role','authenticated')::text, true);
    delete from public.expenses where id=xexp; -- Alice: creator
    if exists (select 1 from public.expenses where id=xexp) then
      raise exception '❌ TEST17: the creator should be able to delete their own expense'; end if;
    if exists (select 1 from public.expense_shares where expense_id=xexp) then
      raise exception '❌ TEST17: deleting the expense should cascade its shares'; end if;

    -- Settle-up: Alice pays 30 split 3 ways -> Bob and Carol each owe Alice 10.
    xexp := public.add_expense(ev, alice, 'Dinner', 30, array[alice,bob,carol]);
    select count(*) into xcnt from public.event_settle_up(ev);
    if xcnt <> 2 then raise exception '❌ TEST17: expected exactly 2 transfers (got %)', xcnt; end if;
    perform 1 from public.event_settle_up(ev) where to_user=alice and amount_cents=10 and from_user=bob;
    if not found then raise exception '❌ TEST17: expected Bob -> Alice 10'; end if;
    perform 1 from public.event_settle_up(ev) where to_user=alice and amount_cents=10 and from_user=carol;
    if not found then raise exception '❌ TEST17: expected Carol -> Alice 10'; end if;

    -- A net-zero event (no expenses) settles to zero rows.
    select count(*) into xcnt from public.event_settle_up(ev_dinner);
    if xcnt <> 0 then raise exception '❌ TEST17: an event with no expenses should settle to zero rows'; end if;

    -- VISIBILITY: Dave is not a member of `ev`, so he reads nothing and gets
    -- zero settle-up rows.
    perform set_config('request.jwt.claims', json_build_object('sub',dave::text,'role','authenticated')::text, true);
    select count(*) into xcnt from public.expenses where event_id=ev;
    if xcnt <> 0 then raise exception '❌ CARDINAL (TEST17): Dave must not read expenses'; end if;
    select count(*) into xcnt from public.expense_shares where event_id=ev;
    if xcnt <> 0 then raise exception '❌ CARDINAL (TEST17): Dave must not read expense_shares'; end if;
    select count(*) into xcnt from public.event_settle_up(ev);
    if xcnt <> 0 then raise exception '❌ CARDINAL (TEST17): Dave must get zero settle-up rows'; end if;
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
